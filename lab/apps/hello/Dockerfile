# Multi-stage, like any production .NET image.
# Build stage carries the SDK (~900 MB); the final image carries only the runtime.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY hello.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS final
WORKDIR /app
COPY --from=build /app .

# Run as a non-root user. The .NET runtime images already ship a user called `app`
# (uid 1654, exported as $APP_UID) - we only have to give it somewhere to write.
# Lesson 20 makes the cluster enforce non-root; doing it in the image is the half you own.
RUN mkdir -p /data && chown -R app:app /data
USER app

ENV ASPNETCORE_URLS=http://0.0.0.0:8080 \
    DOTNET_EnableDiagnostics=0
EXPOSE 8080

ENTRYPOINT ["dotnet", "hello.dll"]
