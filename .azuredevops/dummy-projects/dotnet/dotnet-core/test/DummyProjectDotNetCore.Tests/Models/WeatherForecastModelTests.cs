using DummyProjectDotNetCore.Models;
using Xunit;

namespace DummyProjectDotNetCore.Tests.Models
{
    public class WeatherForecastModelTests
    {
        [Fact]
        public void Date_WhenSet_ReturnsExpectedValue()
        {
            // Arrange
            var model = new WeatherForecastModel();
            var expected = new DateOnly(2026, 3, 30);

            // Act
            model.Date = expected;

            // Assert
            Assert.Equal(expected, model.Date);
        }

        [Fact]
        public void TemperatureC_WhenSet_ReturnsExpectedValue()
        {
            // Arrange
            var model = new WeatherForecastModel();

            // Act
            model.TemperatureC = 25;

            // Assert
            Assert.Equal(25, model.TemperatureC);
        }

        [Theory]
        [InlineData(0, 32)]
        [InlineData(100, 211)]
        [InlineData(-40, -39)]
        public void TemperatureF_ReturnsCorrectConversion(int celsius, int expectedFahrenheit)
        {
            // Arrange
            var model = new WeatherForecastModel { TemperatureC = celsius };

            // Act
            var result = model.TemperatureF;

            // Assert
            Assert.Equal(expectedFahrenheit, result);
        }

        [Fact]
        public void Summary_WhenSet_ReturnsExpectedValue()
        {
            // Arrange
            var model = new WeatherForecastModel();

            // Act
            model.Summary = "Sunny";

            // Assert
            Assert.Equal("Sunny", model.Summary);
        }

        [Fact]
        public void Summary_DefaultsToNull()
        {
            // Arrange & Act
            var model = new WeatherForecastModel();

            // Assert
            Assert.Null(model.Summary);
        }
    }
}
