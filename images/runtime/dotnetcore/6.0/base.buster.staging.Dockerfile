# syntax=docker/dockerfile:1.3
# the above line allows this dockerfile to use the secrets fucntionality

# dotnet tools are currently available as part of SDK so we need to create them in an sdk image
# and copy them to our final runtime image
FROM mcr.microsoft.com/dotnet/sdk:6.0 AS tools-install
RUN dotnet tool install --tool-path /dotnetcore-tools dotnet-sos
RUN dotnet tool install --tool-path /dotnetcore-tools dotnet-trace
RUN dotnet tool install --tool-path /dotnetcore-tools dotnet-dump
RUN dotnet tool install --tool-path /dotnetcore-tools dotnet-counters
RUN dotnet tool install --tool-path /dotnetcore-tools dotnet-gcdump
RUN dotnet tool install --tool-path /dotnetcore-tools dotnet-monitor --version 7.*

FROM mcr.microsoft.com/mirror/docker/library/debian:buster-slim
ARG BUILD_DIR=/tmp/oryx/build
ADD build ${BUILD_DIR}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        # .NET Core dependencies
        libc6 \
        libgcc1 \
        libgssapi-krb5-2 \
        libicu63 \
        libssl1.1 \
        libstdc++6 \
        zlib1g \
        lldb \
        curl \
        file \
        libgdiplus \
    && apt-get upgrade --assume-yes \
    && rm -rf /var/lib/apt/lists/*

# Configure web servers to bind to port 80 when present
ENV ASPNETCORE_URLS=http://+:80 \
    # Enable detection of running in a container
    DOTNET_RUNNING_IN_CONTAINER=true \
    PATH="/opt/dotnetcore-tools:${PATH}"

COPY --from=tools-install /dotnetcore-tools /opt/dotnetcore-tools

# Install .NET Core
# mount the secret sas token to pull the binaries, and make sure we do not print to docker build logs
RUN --mount=type=secret,id=dotnet_storage_account_token_id \
    set -e \
    # based on resolution on https://github.com/NuGet/Announcements/issues/49#issue-795386700
    && apt-get remove ca-certificates -y \
    && apt-get purge ca-certificates -y \
    && apt-get update \
    && apt-get install -f ca-certificates=20200601~deb10u2 -y --no-install-recommends \
    && . ${BUILD_DIR}/__dotNetCoreRunTimeVersions.sh \
    && curl -SL --output dotnet.tar.gz https://dotnetcli.blob.core.windows.net/dotnet-private/Internal/$NET_CORE_APP_60/dotnet-runtime-$NET_CORE_APP_60-linux-x64.tar.gz$(cat /run/secrets/dotnet_storage_account_token_id) \
    && echo "$NET_CORE_APP_60_SHA dotnet.tar.gz" | sha512sum -c - \
    && mkdir -p /usr/share/dotnet \
    && tar -zxf dotnet.tar.gz -C /usr/share/dotnet \
    && rm dotnet.tar.gz \
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
    # Install ASP.NET Core
    && . ${BUILD_DIR}/__dotNetCoreRunTimeVersions.sh \
    && curl -SL --output aspnetcore.tar.gz https://dotnetcli.blob.core.windows.net/dotnet-private/Internal/$ASPNET_CORE_APP_60/aspnetcore-runtime-$ASPNET_CORE_APP_60-linux-x64.tar.gz$(cat /run/secrets/dotnet_storage_account_token_id) \
    && echo "$ASPNET_CORE_APP_60_SHA aspnetcore.tar.gz" | sha512sum -c - \
    && mkdir -p /usr/share/dotnet \
    && tar -zxf aspnetcore.tar.gz -C /usr/share/dotnet ./shared/Microsoft.AspNetCore.App \
    && rm aspnetcore.tar.gz \
    && dotnet-sos install \
    && rm -rf ${BUILD_DIR}