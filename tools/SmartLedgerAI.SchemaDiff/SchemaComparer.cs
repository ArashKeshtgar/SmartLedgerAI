using System.Text;

namespace SmartLedgerAI.SchemaDiff;

public enum DiffKind { OnlyInLeft, OnlyInRight, TypeChanged, DefinitionChanged, ColumnOnlyInLeft, ColumnOnlyInRight, ColumnChanged }

public sealed record SchemaDifference(DiffKind Kind, string Object, string Detail);

public static class SchemaComparer
{
    public static IReadOnlyList<SchemaDifference> Compare(
        IReadOnlyDictionary<string, DbObject> left, IReadOnlyDictionary<string, DbObject> right)
    {
        var diffs = new List<SchemaDifference>();
        var names = left.Keys.Union(right.Keys, StringComparer.OrdinalIgnoreCase)
            .Order(StringComparer.OrdinalIgnoreCase);

        foreach (var name in names)
        {
            left.TryGetValue(name, out var l);
            right.TryGetValue(name, out var r);

            if (r is null) { diffs.Add(new(DiffKind.OnlyInLeft, name, l!.Type)); continue; }
            if (l is null) { diffs.Add(new(DiffKind.OnlyInRight, name, r.Type)); continue; }

            if (!l.Type.Equals(r.Type, StringComparison.OrdinalIgnoreCase))
                diffs.Add(new(DiffKind.TypeChanged, name, $"{l.Type} → {r.Type}"));

            if (l.DefinitionHash != r.DefinitionHash)
                diffs.Add(new(DiffKind.DefinitionChanged, name, l.Type));

            // Views list their columns too, but a view's columns follow from its
            // definition; only report column drift on tables.
            if (!l.Type.Equals("USER_TABLE", StringComparison.OrdinalIgnoreCase))
                continue;

            var columns = l.Columns.Keys.Union(r.Columns.Keys, StringComparer.OrdinalIgnoreCase)
                .Order(StringComparer.OrdinalIgnoreCase);
            foreach (var col in columns)
            {
                l.Columns.TryGetValue(col, out var lc);
                r.Columns.TryGetValue(col, out var rc);
                if (rc is null) diffs.Add(new(DiffKind.ColumnOnlyInLeft, name, $"{col} {lc!.Describe()}"));
                else if (lc is null) diffs.Add(new(DiffKind.ColumnOnlyInRight, name, $"{col} {rc.Describe()}"));
                else if (lc.Describe() != rc.Describe())
                    diffs.Add(new(DiffKind.ColumnChanged, name, $"{col}: {lc.Describe()} → {rc.Describe()}"));
            }
        }
        return diffs;
    }

    public static string ToMarkdown(IReadOnlyList<SchemaDifference> diffs, string leftLabel, string rightLabel,
        int leftCount, int rightCount)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"# Schema comparison: {leftLabel} vs {rightLabel}");
        sb.AppendLine();
        sb.AppendLine($"{leftLabel}: {leftCount} objects · {rightLabel}: {rightCount} objects · {diffs.Count} difference(s)");
        sb.AppendLine();

        if (diffs.Count == 0)
        {
            sb.AppendLine("No differences: the schemas match.");
            return sb.ToString();
        }

        Section(DiffKind.OnlyInLeft, $"Only in {leftLabel}");
        Section(DiffKind.OnlyInRight, $"Only in {rightLabel}");
        Section(DiffKind.TypeChanged, "Object type differs");
        Section(DiffKind.ColumnOnlyInLeft, $"Table columns only in {leftLabel}");
        Section(DiffKind.ColumnOnlyInRight, $"Table columns only in {rightLabel}");
        Section(DiffKind.ColumnChanged, "Table columns with a different type or nullability");
        Section(DiffKind.DefinitionChanged, "Views / procedures / triggers / functions whose code differs");
        return sb.ToString();

        void Section(DiffKind kind, string title)
        {
            var items = diffs.Where(d => d.Kind == kind).ToList();
            if (items.Count == 0) return;
            sb.AppendLine($"## {title} ({items.Count})");
            sb.AppendLine();
            sb.AppendLine("| Object | Detail |");
            sb.AppendLine("|---|---|");
            foreach (var d in items)
                sb.AppendLine($"| `{d.Object}` | {d.Detail.Replace("|", "\\|")} |");
            sb.AppendLine();
        }
    }
}
