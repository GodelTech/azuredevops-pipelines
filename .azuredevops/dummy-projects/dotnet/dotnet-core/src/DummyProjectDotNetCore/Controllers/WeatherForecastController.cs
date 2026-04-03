using DummyProjectDotNetCore.Models;
using DummyProjectDotNetCore.Providers;

using Microsoft.AspNetCore.Mvc;

namespace DummyProjectDotNetCore.Controllers;

/// <summary>Provides weather forecast API endpoints.</summary>
/// <param name="dateTimeProvider">The <see cref="IDateTimeProvider"/> used to obtain the current UTC date and time.</param>
[ApiController]
[Route("[controller]")]
public class WeatherForecastController(IDateTimeProvider dateTimeProvider) : ControllerBase
{
    /// <summary>Returns the current weather forecast.</summary>
    /// <returns>A <see cref="WeatherForecastModel"/> representing the current weather forecast.</returns>
    [HttpGet]
    [ProducesResponseType<WeatherForecastModel>(StatusCodes.Status200OK)]
    public ActionResult<WeatherForecastModel> Get()
    {
        return new WeatherForecastModel(
            Date: DateOnly.FromDateTime(dateTimeProvider.UtcNow),
            TemperatureC: 12,
            Summary: "Mild"
        );
    }
}
