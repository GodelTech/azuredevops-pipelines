using Microsoft.AspNetCore.Mvc.Testing;

using Xunit;

namespace DummyProjectDotNetCore.IntegrationTests;

public class ProgramTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public ProgramTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task GetWeatherForecast_ReturnsSuccess()
    {
        // Arrange
        var client = _factory.CreateClient();

        // Act
        var response = await client.GetAsync(new Uri("/WeatherForecast", UriKind.Relative), TestContext.Current.CancellationToken);

        // Assert
        response.EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task GetWeatherForecast_InDevelopmentEnvironment_ReturnsSuccess()
    {
        // Arrange
        await using var factory = _factory.WithWebHostBuilder(builder =>
            builder.UseSetting("ASPNETCORE_ENVIRONMENT", "Development"));
        var client = factory.CreateClient();

        // Act
        var response = await client.GetAsync(new Uri("/WeatherForecast", UriKind.Relative), TestContext.Current.CancellationToken);

        // Assert
        response.EnsureSuccessStatusCode();
    }
}
