FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["src/SmartLedgerAI.AnomalyNotifier/SmartLedgerAI.AnomalyNotifier.csproj", "src/SmartLedgerAI.AnomalyNotifier/"]
RUN dotnet restore "src/SmartLedgerAI.AnomalyNotifier/SmartLedgerAI.AnomalyNotifier.csproj"
COPY src/SmartLedgerAI.AnomalyNotifier/ src/SmartLedgerAI.AnomalyNotifier/
WORKDIR /src/src/SmartLedgerAI.AnomalyNotifier
RUN dotnet publish "SmartLedgerAI.AnomalyNotifier.csproj" -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/runtime:8.0
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "SmartLedgerAI.AnomalyNotifier.dll"]
