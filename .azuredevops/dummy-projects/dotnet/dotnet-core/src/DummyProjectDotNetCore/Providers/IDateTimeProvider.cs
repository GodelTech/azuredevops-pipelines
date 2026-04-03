namespace DummyProjectDotNetCore.Providers;

/// <summary>Defines a contract for providing the current date and time.</summary>
public interface IDateTimeProvider
{
    /// <summary>Gets the current UTC date and time.</summary>
    public DateTime UtcNow { get; }
}
