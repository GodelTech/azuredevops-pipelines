using DummyProjectDotNetCore.Models;

using Xunit;

namespace DummyProjectDotNetCore.Tests.Models;

public class WeatherForecastModelTests
{
    [Theory]
    [InlineData(0, 32)]
    [InlineData(100, 212)]
    [InlineData(-40, -40)]
    public void TemperatureF_ReturnsCorrectConversion(int celsius, int expectedFahrenheit)
    {
        // Arrange
        var model = new WeatherForecastModel(DateOnly.MinValue, celsius, null);

        // Act
        var result = model.TemperatureF;

        // Assert
        Assert.Equal(expectedFahrenheit, result);
    }
}
