using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Logging.Testing;

using Xunit;

namespace DummyProjectDotNetNuGet.Tests;

public class DummyServiceTests
{
    [Fact]
    public void Greet_WithName_ReturnsExpectedGreeting()
    {
        // Arrange
        var logger = new NullLogger<DummyService>();
        var sut = new DummyService(logger);

        // Act
        var result = sut.Greet("World");

        // Assert
        Assert.Equal("Hello, World!", result);
    }

    [Fact]
    public void Greet_WithName_LogsInformationMessage()
    {
        // Arrange
        var logger = new FakeLogger<DummyService>();
        var sut = new DummyService(logger);

        // Act
        sut.Greet("World");

        // Assert
        var record = Assert.Single(logger.Collector.GetSnapshot());
        Assert.Equal(LogLevel.Information, record.Level);
        Assert.Contains("World", record.Message);
    }
}
