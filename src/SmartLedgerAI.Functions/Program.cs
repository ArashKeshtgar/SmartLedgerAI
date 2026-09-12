using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;

using Azure.Core.Serialization;
using System.Text.Json;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults(builder =>
    {
        builder.Services.Configure<WorkerOptions>(options =>
        {
            options.Serializer = new JsonObjectSerializer(
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
        });
    })
    .Build();

host.Run();