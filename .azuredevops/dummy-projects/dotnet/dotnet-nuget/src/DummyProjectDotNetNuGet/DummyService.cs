using Microsoft.Extensions.Logging;

namespace DummyProjectDotNetNuGet;

/// <summary>Provides greeting functionality.</summary>
/// <remarks>Initializes a new instance of <see cref="DummyService"/>.</remarks>
/// <param name="logger">The logger instance.</param>
public partial class DummyService(ILogger<DummyService> logger)
{
    /// <summary>Returns a greeting for the specified name.</summary>
    /// <param name="name">The name to greet.</param>
    /// <returns>A greeting string.</returns>
    public string Greet(string name)
    {
        LogGreeting(logger, name);

        return $"Hello, {name}!";
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Greeting {Name}")]
    private static partial void LogGreeting(ILogger logger, string name);
}
