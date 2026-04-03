using DummyProjectDotNetCore.Providers;

namespace DummyProjectDotNetCore.Tests.Fakes;

public class FakeDateTimeProvider(DateTime utcNow) : IDateTimeProvider
{
    public DateTime UtcNow => utcNow;
}
