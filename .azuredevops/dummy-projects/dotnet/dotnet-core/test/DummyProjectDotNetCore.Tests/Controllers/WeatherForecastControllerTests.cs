using DummyProjectDotNetCore.Controllers;
using DummyProjectDotNetCore.Models;
using DummyProjectDotNetCore.Tests.Fakes;

using Xunit;

namespace DummyProjectDotNetCore.Tests.Controllers;

public class WeatherForecastControllerTests
{
    [Fact]
    public void Get_ReturnsExpectedWeatherForecast()
    {
        // Arrange
        var utcNow = new DateTime(2026, 4, 3, 0, 0, 0, DateTimeKind.Utc);
        var controller = new WeatherForecastController(new FakeDateTimeProvider(utcNow));
        var expected = new WeatherForecastModel(DateOnly.FromDateTime(utcNow), 12, "Mild");

        // Act
        var result = controller.Get();

        // Assert
        Assert.Equal(expected, Assert.IsType<WeatherForecastModel>(result.Value));
    }
}
