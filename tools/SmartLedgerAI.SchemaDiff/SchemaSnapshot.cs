namespace SmartLedgerAI.SchemaDiff;

public sealed record ColumnInfo(int Id, string Name, string DataType, int MaxLength, int Precision, int Scale, bool IsNullable)
{
    public string Describe()
    {
        var type = DataType.ToLowerInvariant() switch
        {
            "varchar" or "char" or "varbinary" or "binary" => $"{DataType}({(MaxLength == -1 ? "max" : MaxLength.ToString())})",
            "nvarchar" or "nchar" => $"{DataType}({(MaxLength == -1 ? "max" : (MaxLength / 2).ToString())})",
            "decimal" or "numeric" => $"{DataType}({Precision},{Scale})",
            _ => DataType,
        };
        return $"{type} {(IsNullable ? "NULL" : "NOT NULL")}";
    }
}

public sealed class DbObject(string schema, string name, string type)
{
    public string Schema { get; } = schema;
    public string Name { get; } = name;
    public string Type { get; } = type;
    public string? DefinitionHash { get; set; }
    public Dictionary<string, ColumnInfo> Columns { get; } = new(StringComparer.OrdinalIgnoreCase);

    public string FullName => $"{Schema}.{Name}";
}

// Reads what sql/phase0/schema_snapshot.sql produces: a CSV export with headers
// (Azure Portal query editor, SSMS "Save Results As"), in any column order, or
// a tab-separated grid copied from SSMS without headers, in the query's order.
public static class SchemaSnapshot
{
    private static readonly string[] QueryColumns =
    [
        "SchemaName", "ObjectName", "ObjectType", "ColumnId", "ColumnName", "DataType",
        "MaxLength", "Precision", "Scale", "IsNullable", "DefinitionHash",
    ];

    public static Dictionary<string, DbObject> Parse(string text)
    {
        var firstLine = text.Split('\n', 2)[0];
        var rows = Csv.Parse(text, firstLine.Contains('\t') ? '\t' : ',');
        if (rows.Count == 0)
            throw new FormatException("Snapshot is empty.");

        var hasHeader = rows[0].Any(h => h.Trim().Equals("SchemaName", StringComparison.OrdinalIgnoreCase));
        if (!hasHeader)
            rows.Insert(0, [.. QueryColumns]);

        var header = rows[0].Select(h => h.Trim()).ToList();
        int Col(string name)
        {
            var i = header.FindIndex(h => h.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (i < 0) throw new FormatException($"Snapshot is missing the '{name}' column.");
            return i;
        }

        int schema = Col("SchemaName"), obj = Col("ObjectName"), type = Col("ObjectType"),
            colId = Col("ColumnId"), colName = Col("ColumnName"), dataType = Col("DataType"),
            maxLen = Col("MaxLength"), prec = Col("Precision"), scale = Col("Scale"),
            nullable = Col("IsNullable"), hash = Col("DefinitionHash");

        var objects = new Dictionary<string, DbObject>(StringComparer.OrdinalIgnoreCase);
        for (var line = 2; line <= rows.Count; line++)
        {
            var row = rows[line - 1];
            if (row.All(v => v.Trim().Length == 0))
                continue;
            var userLine = hasHeader ? line : line - 1; // the header we inserted is not in their file

            string Get(int i) => i < row.Count ? Value(row[i]) : "";
            int Int(int i) => Get(i) is var v && v.Length == 0 ? 0
                : int.TryParse(v, out var n) ? n
                : throw new FormatException($"Snapshot line {userLine}: '{v}' is not a number. Was the CSV exported with the query's columns?");

            var o = new DbObject(Get(schema), Get(obj), Get(type));
            if (!objects.TryGetValue(o.FullName, out var existing))
                objects[o.FullName] = existing = o;

            if (Get(hash).Length > 0)
                existing.DefinitionHash = Get(hash).ToUpperInvariant();

            if (Get(colName).Length > 0)
            {
                existing.Columns[Get(colName)] = new ColumnInfo(
                    Int(colId), Get(colName), Get(dataType),
                    Int(maxLen), Int(prec), Int(scale), Bool(Get(nullable)));
            }
        }
        return objects;
    }

    // Exports write SQL NULL as an empty cell or as the literal NULL.
    private static string Value(string raw)
    {
        var v = raw.Trim();
        return v.Equals("NULL", StringComparison.OrdinalIgnoreCase) ? "" : v;
    }

    private static bool Bool(string v) => v is "1" || v.Equals("true", StringComparison.OrdinalIgnoreCase);
}

internal static class Csv
{
    // RFC 4180: quoted fields, doubled quotes, commas and newlines inside quotes.
    public static List<List<string>> Parse(string text, char delimiter)
    {
        var rows = new List<List<string>>();
        var row = new List<string>();
        var field = new System.Text.StringBuilder();
        var quoted = false;

        for (var i = 0; i < text.Length; i++)
        {
            var ch = text[i];
            if (quoted)
            {
                if (ch == '"' && i + 1 < text.Length && text[i + 1] == '"') { field.Append('"'); i++; }
                else if (ch == '"') quoted = false;
                else field.Append(ch);
                continue;
            }

            switch (ch)
            {
                case '"': quoted = true; break;
                case var d when d == delimiter: row.Add(field.ToString()); field.Clear(); break;
                case '\r': break;
                case '\n': row.Add(field.ToString()); field.Clear(); rows.Add(row); row = []; break;
                case '﻿' when i == 0: break;
                default: field.Append(ch); break;
            }
        }

        if (field.Length > 0 || row.Count > 0)
        {
            row.Add(field.ToString());
            rows.Add(row);
        }
        return rows;
    }
}
