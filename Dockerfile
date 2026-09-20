FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["src/SmartLedgerAI.Functions/SmartLedgerAI_Functions.csproj", "src/SmartLedgerAI.Functions/"]
RUN dotnet restore "src/SmartLedgerAI.Functions/SmartLedgerAI_Functions.csproj"
COPY src/SmartLedgerAI.Functions/ src/SmartLedgerAI.Functions/
WORKDIR /src/src/SmartLedgerAI.Functions
RUN dotnet publish "SmartLedgerAI_Functions.csproj" -c Release -o /app/publish

FROM mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated8.0
WORKDIR /home/site/wwwroot
COPY --from=build /app/publish .
ENV AzureFunctionsJobHost__Logging__Console__IsEnabled=true
