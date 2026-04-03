namespace DummyProjectDotNetCore.Models;

/// <summary>Represents a weather forecast for a specific date.</summary>
/// <param name="Date">The forecast date.</param>
/// <param name="TemperatureC">The temperature in degrees Celsius.</param>
/// <param name="Summary">A short description of the weather, or <c>null</c> if unavailable.</param>
public record WeatherForecastModel(DateOnly Date, int TemperatureC, string? Summary)
{
    /// <summary>Gets the temperature in degrees Fahrenheit, converted from <see cref="TemperatureC"/>.</summary>
    public int TemperatureF => TemperatureC * 9 / 5 + 32;

    /// <summary>Gets a human-readable description based on temperature.</summary>
    public string GetDescription()
    {
        return TemperatureC switch
        {
            < 0 => "Freezing",
            < 10 => "Cold",
            < 20 => "Mild",
            _ => "Hot"
        };
    }
}
