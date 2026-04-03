using Microsoft.AspNetCore.Mvc;

using DummyProjectDotNetCore.Models;

namespace DummyProjectDotNetCore.Controllers;

[ApiController]
[Route("[controller]")]
public class WeatherForecastController : ControllerBase
{
    [HttpGet(Name = "Current")]
    [ProducesResponseType<WeatherForecastModel>(StatusCodes.Status200OK)]
    public ActionResult<WeatherForecastModel> Get()
    {
        return new WeatherForecastModel(
            Date: DateOnly.FromDateTime(DateTime.UtcNow),
            TemperatureC: 12,
            Summary: "Mild"
        );
    }
}
