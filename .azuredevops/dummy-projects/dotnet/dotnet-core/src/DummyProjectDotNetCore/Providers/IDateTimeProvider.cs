namespace DummyProjectDotNetCore.Providers;

public interface IDateTimeProvider
{
    public DateTime UtcNow { get; }
}
