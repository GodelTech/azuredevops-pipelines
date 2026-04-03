using DummyProjectDotNetCore.Models;
using DummyProjectDotNetCore.Providers;

using Microsoft.AspNetCore.Mvc;

namespace DummyProjectDotNetCore.Controllers;

[ApiController]
[Route("[controller]")]
public class WeatherForecastController(IDateTimeProvider dateTimeProvider) : ControllerBase
{
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
