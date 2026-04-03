using DummyProjectDotNetCore.Controllers;
using DummyProjectDotNetCore.Models;

using Xunit;

namespace DummyProjectDotNetCore.Tests.Controllers;

public class WeatherForecastControllerTests
{
    [Fact]
    public void Get_ReturnsTemperatureC_EqualTo12()
    {
        // Arrange
        var controller = new WeatherForecastController();

        // Act
        var result = controller.Get();

        // Assert
        Assert.Equal(12, Assert.IsType<WeatherForecastModel>(result.Value).TemperatureC);
    }

    [Fact]
    public void Get_ReturnsSummary_EqualToMild()
    {
        // Arrange
        var controller = new WeatherForecastController();

        // Act
        var result = controller.Get();

        // Assert
        Assert.Equal("Mild", Assert.IsType<WeatherForecastModel>(result.Value).Summary);
    }

    [Fact]
    public void Get_ReturnsDate_EqualToToday()
    {
        // Arrange
        var controller = new WeatherForecastController();
        var before = DateOnly.FromDateTime(DateTime.UtcNow);

        // Act
        var result = controller.Get();

        // Assert
        var after = DateOnly.FromDateTime(DateTime.UtcNow);
        Assert.InRange(Assert.IsType<WeatherForecastModel>(result.Value).Date, before, after);
    }
}
