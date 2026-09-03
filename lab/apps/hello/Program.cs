// hello - the course's own workload.
//
// Deliberately small, and deliberately equipped with every endpoint the later
// lessons need: a liveness probe that always answers, a readiness probe that is
// slow on purpose, a config dump for the ConfigMap/Secret lesson, a way to crash
// on demand, a CPU burner for autoscaling, and a writable-path check for volumes.
//
// Everything is controlled by environment variables so the same image can behave
// differently in each lesson - which is the entire point of the twelve-factor
// style Kubernetes expects.

using System.Diagnostics;
using System.Text;

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(o => { o.SingleLine = true; o.TimestampFormat = "HH:mm:ss "; });

var app = builder.Build();

string Env(string key, string fallback) =>
    Environment.GetEnvironmentVariable(key) is { Length: > 0 } v ? v : fallback;

var version      = Env("APP_VERSION", "dev");
var greeting     = Env("GREETING", "hello");
var readyAfter   = int.TryParse(Env("READY_AFTER_SECONDS", "0"), out var r) ? r : 0;
var failLiveness = Env("FAIL_LIVENESS_AFTER_SECONDS", "0");
var dataDir      = Env("DATA_DIR", "/data");
var host         = Environment.MachineName;   // in a Pod this is the Pod name
var started      = Stopwatch.StartNew();

app.Logger.LogInformation("hello {Version} starting on {Host}; ready after {Ready}s", version, host, readyAfter);

// The main page. Curl this from another Pod to see load balancing pick different hosts.
// The catch-all means every path answers, so an Ingress can route /api straight here
// without a rewrite rule; the received path is echoed back so you can see what arrived.
string Page(HttpContext ctx) =>
    $"{greeting} from {host}\nversion: {version}\npath: {ctx.Request.Path}\n" +
    $"uptime: {started.Elapsed.TotalSeconds:F0}s\n";

app.MapGet("/", (HttpContext ctx) => Results.Text(Page(ctx)));
app.MapGet("/{**rest}", (HttpContext ctx) => Results.Text(Page(ctx)));

// Liveness: "is the process wedged?" Answers immediately, forever - unless you ask it
// to start failing, which is how lesson 14 demonstrates a restart loop.
app.MapGet("/healthz", () =>
{
    if (int.TryParse(failLiveness, out var after) && after > 0 && started.Elapsed.TotalSeconds > after)
        return Results.StatusCode(500);
    return Results.Text("ok");
});

// Readiness: "should traffic come here yet?" Deliberately slow to become true.
app.MapGet("/readyz", () =>
    started.Elapsed.TotalSeconds < readyAfter
        ? Results.StatusCode(503)
        : Results.Text("ready"));

// What configuration did this Pod actually receive? Environment variables plus every
// file mounted under /etc/hello - which is how ConfigMaps and Secrets arrive.
app.MapGet("/config", () =>
{
    var sb = new StringBuilder();
    sb.AppendLine("# environment (APP_/GREETING/DB_ only)");
    foreach (System.Collections.DictionaryEntry e in Environment.GetEnvironmentVariables())
    {
        var key = (string)e.Key;
        if (key.StartsWith("APP_") || key.StartsWith("DB_") || key == "GREETING")
            sb.AppendLine($"{key}={e.Value}");
    }
    sb.AppendLine();
    sb.AppendLine("# files under /etc/hello");
    if (Directory.Exists("/etc/hello"))
        foreach (var f in Directory.GetFiles("/etc/hello"))
            sb.AppendLine($"{f} = {File.ReadAllText(f).Trim()}");
    else
        sb.AppendLine("(nothing mounted)");
    return Results.Text(sb.ToString());
});

// Volumes: write a line, then read the whole file back. Survives a restart only if the
// path is backed by something that outlives the container.
app.MapGet("/data", () =>
{
    var file = Path.Combine(dataDir, "log.txt");
    try
    {
        Directory.CreateDirectory(dataDir);
        File.AppendAllText(file, $"{DateTime.UtcNow:O} {host}\n");
        return Results.Text(File.ReadAllText(file));
    }
    catch (Exception ex)
    {
        return Results.Text($"cannot write {file}: {ex.GetType().Name}: {ex.Message}", statusCode: 500);
    }
});

// Crash on demand - for CrashLoopBackOff and restartPolicy.
app.MapGet("/crash", () =>
{
    app.Logger.LogError("crashing on request");
    _ = Task.Run(async () => { await Task.Delay(100); Environment.Exit(1); });
    return Results.Text("crashing");
});

// Burn CPU - for the HorizontalPodAutoscaler lesson.
app.MapGet("/burn", (int seconds) =>
{
    var until = DateTime.UtcNow.AddSeconds(Math.Clamp(seconds, 1, 300));
    while (DateTime.UtcNow < until) { _ = Math.Sqrt(Random.Shared.NextDouble()); }
    return Results.Text($"burned {seconds}s on {host}");
});

// Allocate memory - for resource limits and OOMKilled.
app.MapGet("/eat", (int mb) =>
{
    var blocks = new List<byte[]>();
    for (var i = 0; i < Math.Clamp(mb, 1, 4096); i++)
    {
        var b = new byte[1024 * 1024];
        Array.Fill(b, (byte)1);   // touch it, or it is never really allocated
        blocks.Add(b);
    }
    return Results.Text($"holding {blocks.Count} MB on {host}");
});

app.Run("http://0.0.0.0:8080");
