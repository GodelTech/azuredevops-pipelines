var builder = WebApplication.CreateBuilder(args);

_ = builder.Services.AddControllers();
_ = builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    _ = app.MapOpenApi();
}

_ = app.UseHttpsRedirection();

_ = app.UseAuthorization();

_ = app.MapControllers();

await app.RunAsync();
