namespace DummyProjectDotNetCore.Providers;

public interface IDateTimeProvider
{
    DateTime UtcNow { get; }
}
