#!/usr/bin/env bash
# Runs the SQL scripts in sql/ and their tests on throwaway databases in a SQL Server container.
#   MSSQL_CONTAINER   the container's name or id (default: mssql)
#   MSSQL_SA_PASSWORD the sa password
# Local: docker run -d --name mssql -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD=... mcr.microsoft.com/mssql/server:2022-latest
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
container=${MSSQL_CONTAINER:-mssql}
: "${MSSQL_SA_PASSWORD:?set MSSQL_SA_PASSWORD}"

sql() { docker exec -i "$container" /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -b -I "$@"; }
run() { echo "-- $2"; sql -d "$1" < "$root/$2"; }
fresh() { sql -Q "IF DB_ID(N'$1') IS NOT NULL DROP DATABASE [$1]; CREATE DATABASE [$1];"; run "$1" tests/sql/powerapp_fixture.sql; }

for _ in $(seq 1 60); do sql -Q "SELECT 1" > /dev/null 2>&1 && break; sleep 2; done

echo "== Option A: expense writes through procedures"
fresh Fixture
fresh OptionA
run OptionA sql/phase0/002_expense_writes_via_procedures.sql
run OptionA sql/phase0/002_expense_writes_via_procedures.sql
run OptionA sql/phase0/002_expense_writes_via_procedures.test.sql
run OptionA sql/phase0/002_expense_writes_via_procedures.rollback.sql
changed=$(sql -h -1 -W -Q "SET NOCOUNT ON;
SELECT o.name FROM Fixture.sys.sql_modules m JOIN Fixture.sys.objects o ON o.object_id = m.object_id
LEFT JOIN OptionA.sys.objects o2 ON o2.name = o.name LEFT JOIN OptionA.sys.sql_modules m2 ON m2.object_id = o2.object_id
WHERE m2.definition IS NULL OR m2.definition <> m.definition
UNION ALL SELECT name FROM OptionA.sys.objects WHERE name IN (N'fn_IsPeriodClosed', N'sp_AssignExpensePeriod', N'sp_UpdateExpense', N'sp_ApproveExpense', N'sp_RejectExpense', N'sp_DeleteExpense');")
if [ -n "$changed" ]; then echo "FAIL rollback left these different from the original: $changed"; exit 1; fi
echo "PASS rollback restores the original objects"

echo "== Option B+: closed-period constraints"
fresh OptionB
run OptionB sql/phase0/003_closed_period_constraints.sql
run OptionB sql/phase0/003_closed_period_constraints.sql
run OptionB sql/phase0/003_closed_period_constraints.test.sql
run OptionB sql/phase0/003_closed_period_constraints.rollback.sql
changed=$(sql -h -1 -W -Q "SET NOCOUNT ON;
SELECT o.name FROM Fixture.sys.sql_modules m JOIN Fixture.sys.objects o ON o.object_id = m.object_id
LEFT JOIN OptionB.sys.objects o2 ON o2.name = o.name LEFT JOIN OptionB.sys.sql_modules m2 ON m2.object_id = o2.object_id
WHERE m2.definition IS NULL OR m2.definition <> m.definition
UNION ALL SELECT name FROM OptionB.sys.objects WHERE name IN (N'fn_IsPeriodClosed', N'fn_ExpenseRowWritable', N'CK_Expenses_PeriodOpen', N'CK_Expenses_DecisionHasApprover');")
if [ -n "$changed" ]; then echo "FAIL rollback left these different from the original: $changed"; exit 1; fi
echo "PASS rollback restores the original objects"

echo "== Audit exception queue"
fresh Audit
run Audit sql/audit/001_exception_queue.sql
run Audit sql/audit/001_exception_queue.sql
run Audit sql/audit/001_exception_queue.test.sql
