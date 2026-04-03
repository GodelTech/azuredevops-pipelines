using Xunit;

namespace DummyProjectDotNetCore.IntegrationTests.Controllers;

public class WeatherForecastControllerTests : IClassFixture<WebApplicationFixture>
{
    private readonly WebApplicationFixture _fixture;

    public WeatherForecastControllerTests(WebApplicationFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task GetWeatherForecast_ReturnsSuccess()
    {
        // Arrange
        var client = _fixture.CreateClient();

        // Act
        var response = await client.GetAsync(new Uri("/WeatherForecast", UriKind.Relative), TestContext.Current.CancellationToken);

        // Assert
        Assert.True(response.IsSuccessStatusCode);
    }
}
