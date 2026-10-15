using SmartLedgerAI.SchemaDiff;

// Usage: dotnet run --project tools/SmartLedgerAI.SchemaDiff -- <azure.csv> <local.csv> [report.md]
// Exit code: 0 = schemas match, 1 = differences found, 2 = bad input.
if (args.Length is < 2 or > 3)
{
    Console.Error.WriteLine("Usage: SchemaDiff <azure.csv> <local.csv> [report.md]");
    return 2;
}

try
{
    var left = SchemaSnapshot.Parse(File.ReadAllText(args[0]));
    var right = SchemaSnapshot.Parse(File.ReadAllText(args[1]));
    var diffs = SchemaComparer.Compare(left, right);

    var report = SchemaComparer.ToMarkdown(diffs,
        Path.GetFileNameWithoutExtension(args[0]), Path.GetFileNameWithoutExtension(args[1]),
        left.Count, right.Count);

    if (args.Length == 3)
        File.WriteAllText(args[2], report);
    Console.WriteLine(report);

    return diffs.Count == 0 ? 0 : 1;
}
catch (Exception ex) when (ex is FormatException or IOException)
{
    Console.Error.WriteLine(ex.Message);
    return 2;
}
