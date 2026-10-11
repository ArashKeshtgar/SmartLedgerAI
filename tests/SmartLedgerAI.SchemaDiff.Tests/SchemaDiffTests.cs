using SmartLedgerAI.SchemaDiff;

namespace SmartLedgerAI.SchemaDiff.Tests;

public class SchemaDiffTests
{
    private const string Header =
        "SchemaName,ObjectName,ObjectType,ColumnId,ColumnName,DataType,MaxLength,Precision,Scale,IsNullable,DefinitionHash\n";

    private const string Base = Header +
        "dbo,Expenses,USER_TABLE,1,ExpenseId,int,4,10,0,0,NULL\n" +
        "dbo,Expenses,USER_TABLE,2,Amount,decimal,9,18,2,0,NULL\n" +
        "dbo,Expenses,USER_TABLE,3,Note,nvarchar,200,0,0,1,NULL\n" +
        "dbo,vw_ExpenseList,VIEW,1,ExpenseId,int,4,10,0,0,AA11\n" +
        "dbo,trg_BlockChangesOnClosedPeriod,SQL_TRIGGER,,,,,,,,BB22\n";

    private static IReadOnlyList<SchemaDifference> Diff(string left, string right) =>
        SchemaComparer.Compare(SchemaSnapshot.Parse(left), SchemaSnapshot.Parse(right));

    [Fact]
    public void IdenticalSnapshots_HaveNoDifferences()
    {
        Assert.Empty(Diff(Base, Base));
    }

    [Fact]
    public void Parse_GroupsColumnsByObject_AndReadsObjectsWithoutColumns()
    {
        var objects = SchemaSnapshot.Parse(Base);

        Assert.Equal(3, objects.Count);
        Assert.Equal(3, objects["dbo.Expenses"].Columns.Count);
        Assert.Equal("BB22", objects["dbo.trg_BlockChangesOnClosedPeriod"].DefinitionHash);
        Assert.Empty(objects["dbo.trg_BlockChangesOnClosedPeriod"].Columns);
    }

    [Fact]
    public void Parse_HandlesQuotedFieldsBomAndCrlf_AndAnyColumnOrder()
    {
        var csv = "﻿ObjectName,SchemaName,ObjectType,ColumnId,ColumnName,DataType,MaxLength,Precision,Scale,IsNullable,DefinitionHash\r\n" +
                  "\"Odd, \"\"name\"\"\",dbo,USER_TABLE,1,Id,int,4,10,0,false,\r\n";

        var obj = Assert.Single(SchemaSnapshot.Parse(csv)).Value;

        Assert.Equal("dbo.Odd, \"name\"", obj.FullName);
        Assert.False(obj.Columns["Id"].IsNullable);
    }

    [Fact]
    public void Parse_ReadsHeaderlessTabSeparatedCopyFromSsms()
    {
        var tsv = "dbo\tExpenses\tUSER_TABLE\t1\tAmount\tdecimal\t9\t12\t2\t0\tNULL\n" +
                  "dbo\ttrg_X\tSQL_TRIGGER\tNULL\tNULL\tNULL\tNULL\tNULL\tNULL\tNULL\tAB\n";

        var objects = SchemaSnapshot.Parse(tsv);

        Assert.Equal("decimal(12,2) NOT NULL", objects["dbo.Expenses"].Columns["Amount"].Describe());
        Assert.Equal("AB", objects["dbo.trg_X"].DefinitionHash);
    }

    [Fact]
    public void Parse_HeaderlessErrors_UseTheUsersLineNumbers()
    {
        var ex = Assert.Throws<FormatException>(() => SchemaSnapshot.Parse("dbo\tT\tUSER_TABLE\tx\tId\tint\t4\t10\t0\t0\tNULL\n"));

        Assert.Contains("line 1", ex.Message);
    }

    [Fact]
    public void Parse_RejectsSnapshotWithoutRequiredColumns()
    {
        Assert.Throws<FormatException>(() => SchemaSnapshot.Parse("SchemaName,ObjectName\ndbo,X\n"));
    }

    [Fact]
    public void Parse_NamesTheLineOfAMalformedRow()
    {
        var ex = Assert.Throws<FormatException>(() => SchemaSnapshot.Parse(Header + "dbo,T,USER_TABLE,x,Id,int,4,10,0,0,\n"));

        Assert.Contains("line 2", ex.Message);
    }

    [Fact]
    public void ReportsObjectsMissingOnEitherSide()
    {
        var right = Base.Replace("dbo,vw_ExpenseList,VIEW,1,ExpenseId,int,4,10,0,0,AA11\n", "") +
                    "gl,Account,USER_TABLE,1,Code,varchar,10,0,0,0,NULL\n";

        var diffs = Diff(Base, right);

        Assert.Contains(diffs, d => d is { Kind: DiffKind.OnlyInLeft, Object: "dbo.vw_ExpenseList" });
        Assert.Contains(diffs, d => d is { Kind: DiffKind.OnlyInRight, Object: "gl.Account" });
    }

    [Fact]
    public void ReportsTableColumnChanges_WithReadableTypes()
    {
        var right = Base
            .Replace("2,Amount,decimal,9,18,2,0", "2,Amount,decimal,9,19,4,0")
            .Replace("dbo,Expenses,USER_TABLE,3,Note,nvarchar,200,0,0,1,NULL\n", "") +
            "dbo,Expenses,USER_TABLE,4,TaxAmount,decimal,9,18,2,1,NULL\n";

        var diffs = Diff(Base, right);

        Assert.Contains(diffs, d => d is { Kind: DiffKind.ColumnChanged } && d.Detail == "Amount: decimal(18,2) NOT NULL → decimal(19,4) NOT NULL");
        Assert.Contains(diffs, d => d is { Kind: DiffKind.ColumnOnlyInLeft } && d.Detail == "Note nvarchar(100) NULL");
        Assert.Contains(diffs, d => d is { Kind: DiffKind.ColumnOnlyInRight } && d.Detail.StartsWith("TaxAmount"));
    }

    [Fact]
    public void ReportsChangedCode_ButNotViewColumnDrift()
    {
        var right = Base
            .Replace("BB22", "CC33")
            .Replace("dbo,vw_ExpenseList,VIEW,1,ExpenseId,int,4,10,0,0,AA11", "dbo,vw_ExpenseList,VIEW,1,ExpenseId,bigint,8,19,0,0,AA11");

        var diff = Assert.Single(Diff(Base, right));

        Assert.Equal(DiffKind.DefinitionChanged, diff.Kind);
        Assert.Equal("dbo.trg_BlockChangesOnClosedPeriod", diff.Object);
    }

    [Fact]
    public void Markdown_SaysSoWhenSchemasMatch()
    {
        var report = SchemaComparer.ToMarkdown([], "azure", "local", 3, 3);

        Assert.Contains("No differences", report);
    }
}
