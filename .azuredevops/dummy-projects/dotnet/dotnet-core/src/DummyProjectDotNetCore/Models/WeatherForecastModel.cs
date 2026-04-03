namespace DummyProjectDotNetCore.Models;

public record WeatherForecastModel(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => TemperatureC * 9 / 5 + 32;
}
