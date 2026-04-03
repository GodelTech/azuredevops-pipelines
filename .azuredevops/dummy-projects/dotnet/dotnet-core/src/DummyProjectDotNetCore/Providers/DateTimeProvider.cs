namespace DummyProjectDotNetCore.Providers;

/// <summary>Provides the current system date and time.</summary>
public class DateTimeProvider : IDateTimeProvider
{
    /// <inheritdoc />
    public DateTime UtcNow => DateTime.UtcNow;
}
