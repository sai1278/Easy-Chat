#!/usr/bin/env python3
"""
Isolated Acceptance Test Harness for deliver-migrations.sh
Tests the delivery runner without requiring a live Kubernetes cluster.
Mocks kubectl behavior via a stub script and verifies all edge cases,
fail-closed behaviors, credential redaction, and idempotency paths.
"""

import os
import sys
import shutil
import tempfile
import subprocess

def run_test_case(name, setup_fn, expected_exit_code, expected_output_substrings, forbidden_output_substrings=None, env_vars=None):
    print(f"\n========================================================")
    print(f"RUNNING TEST: {name}")
    print(f"========================================================")

    test_dir = tempfile.mkdtemp(prefix="test_deliver_")
    try:
        # Create directory layout
        scripts_dir = os.path.join(test_dir, "infrastructure", "scripts")
        k8s_dir = os.path.join(test_dir, "infrastructure", "kubernetes", "production")
        migrations_dir = os.path.join(test_dir, "database", "migrations")
        bin_dir = os.path.join(test_dir, "bin")
        os.makedirs(scripts_dir, exist_ok=True)
        os.makedirs(k8s_dir, exist_ok=True)
        os.makedirs(migrations_dir, exist_ok=True)
        os.makedirs(bin_dir, exist_ok=True)

        # Resolve repository root dynamically
        cur = os.path.abspath(os.path.dirname(__file__))
        repo_root = None
        while cur != os.path.dirname(cur):
            if os.path.exists(os.path.join(cur, "infrastructure", "scripts", "deliver-migrations.sh")):
                repo_root = cur
                break
            cur = os.path.dirname(cur)
        if not repo_root:
            repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

        real_script = os.path.join(repo_root, "infrastructure", "scripts", "deliver-migrations.sh")
        target_script = os.path.join(scripts_dir, "deliver-migrations.sh")
        shutil.copy2(real_script, target_script)
        os.chmod(target_script, 0o755)

        # Copy migration-job.yaml
        real_job = os.path.join(repo_root, "infrastructure", "kubernetes", "production", "migration-job.yaml")
        shutil.copy2(real_job, os.path.join(k8s_dir, "migration-job.yaml"))

        # Copy all canonical migration files by default
        real_migrations = os.path.join(repo_root, "database", "migrations")
        for f in os.listdir(real_migrations):
            shutil.copy2(os.path.join(real_migrations, f), os.path.join(migrations_dir, f))

        # Setup scenario-specific conditions
        # setup_fn returns mock_kubectl script content
        mock_kubectl_content = setup_fn(test_dir, migrations_dir, k8s_dir)

        # Write mock kubectl
        mock_kubectl_path = os.path.join(bin_dir, "kubectl")
        with open(mock_kubectl_path, "w", newline="\n") as f:
            f.write(mock_kubectl_content)
        os.chmod(mock_kubectl_path, 0o755)

        # Build environment
        test_env = os.environ.copy()
        test_env["PATH"] = bin_dir + os.pathsep + test_env.get("PATH", "")
        if env_vars:
            test_env.update(env_vars)

        # Run deliver-migrations.sh
        git_bash = r"C:\Program Files\Git\bin\bash.exe"
        bash_bin = git_bash if os.path.exists(git_bash) else "bash"
        cmd = [bash_bin, "infrastructure/scripts/deliver-migrations.sh"]
        proc = subprocess.run(
            cmd,
            cwd=test_dir,
            env=test_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )

        output = proc.stdout
        print(f"Exit code: {proc.returncode} (expected: {expected_exit_code})")
        print("--- Output excerpt ---")
        lines = output.strip().splitlines()
        for l in lines[:25]:
            print(" ", l)
        if len(lines) > 25:
            print(f"  ... [{len(lines)-25} more lines]")

        # Check exit code
        if proc.returncode != expected_exit_code:
            print(f"FAILED: Exit code {proc.returncode} != {expected_exit_code}")
            return False

        # Check expected substrings
        for sub in expected_output_substrings:
            if sub not in output:
                print(f"FAILED: Expected substring not found: '{sub}'")
                return False

        # Check forbidden substrings
        if forbidden_output_substrings:
            for sub in forbidden_output_substrings:
                if sub in output:
                    print(f"FAILED: Forbidden substring found in output: '{sub}'")
                    return False

        print(f"PASSED: {name}")
        return True

    finally:
        shutil.rmtree(test_dir, ignore_errors=True)

def main():
    results = []

    # 1. Missing required migration file
    def setup_case1(test_dir, migrations_dir, k8s_dir):
        # Remove 000005 up file
        for f in os.listdir(migrations_dir):
            if "000005" in f and f.endswith(".up.sql"):
                os.remove(os.path.join(migrations_dir, f))
        return "#!/usr/bin/env bash\necho 'MOCK KUBECTL SHOULD NOT BE CALLED' >&2\nexit 99\n"

    results.append(run_test_case(
        name="Case 1: Missing required migration file (000005.up.sql) triggers preflight failure",
        setup_fn=setup_case1,
        expected_exit_code=1,
        expected_output_substrings=[
            "Required migration 000005 (.up.sql) is missing",
            "Preflight migration inventory validation failed"
        ],
        forbidden_output_substrings=["MOCK KUBECTL SHOULD NOT BE CALLED"]
    ))

    # 2. Duplicate migration version files
    def setup_case2(test_dir, migrations_dir, k8s_dir):
        # Add duplicate for 000007
        dup = os.path.join(migrations_dir, "000007_duplicate_locations.up.sql")
        with open(dup, "w") as f:
            f.write("-- duplicate")
        return "#!/usr/bin/env bash\necho 'MOCK KUBECTL SHOULD NOT BE CALLED' >&2\nexit 99\n"

    results.append(run_test_case(
        name="Case 2: Duplicate migration version files rejected before Kubernetes mutation",
        setup_fn=setup_case2,
        expected_exit_code=1,
        expected_output_substrings=[
            "Duplicate migration files detected for version 000007",
            "Preflight migration inventory validation failed"
        ],
        forbidden_output_substrings=["MOCK KUBECTL SHOULD NOT BE CALLED"]
    ))

    # 3. Missing down migration file
    def setup_case3(test_dir, migrations_dir, k8s_dir):
        # Remove 000003 down file
        for f in os.listdir(migrations_dir):
            if "000003" in f and f.endswith(".down.sql"):
                os.remove(os.path.join(migrations_dir, f))
        return "#!/usr/bin/env bash\necho 'MOCK KUBECTL SHOULD NOT BE CALLED' >&2\nexit 99\n"

    results.append(run_test_case(
        name="Case 3: Missing required down migration file (000003.down.sql) triggers preflight failure",
        setup_fn=setup_case3,
        expected_exit_code=1,
        expected_output_substrings=[
            "Required down migration 000003 (.down.sql) is missing",
            "Preflight migration inventory validation failed"
        ],
        forbidden_output_substrings=["MOCK KUBECTL SHOULD NOT BE CALLED"]
    ))

    # 4. Namespace mismatch with Job manifest
    def setup_case4(test_dir, migrations_dir, k8s_dir):
        return "#!/usr/bin/env bash\nexit 0\n"

    results.append(run_test_case(
        name="Case 4: Environment NAMESPACE mismatch with manifest namespace fails fast",
        setup_fn=setup_case4,
        expected_exit_code=1,
        expected_output_substrings=[
            "Namespace mismatch: environment NAMESPACE='staging' conflicts with manifest namespace 'default'"
        ],
        env_vars={"NAMESPACE": "staging"}
    ))

    # 5. ConfigMap creation/apply failure
    def setup_case5(test_dir, migrations_dir, k8s_dir):
        return """#!/usr/bin/env bash
if [ "$1" = "create" ] && [ "$2" = "configmap" ]; then
    echo "Simulated configmap creation network failure" >&2
    exit 1
fi
exit 0
"""
    results.append(run_test_case(
        name="Case 5: ConfigMap creation failure stops workflow",
        setup_fn=setup_case5,
        expected_exit_code=1,
        expected_output_substrings=[
            "Failed to create or apply ConfigMap easychat-db-migrations"
        ]
    ))

    # 6. Existing FAILED Job causes hard stop and preserves Job
    def setup_case6(test_dir, migrations_dir, k8s_dir):
        return """#!/usr/bin/env bash
if [ "$1" = "create" ] && [ "$2" = "configmap" ]; then
    exit 0
elif [ "$1" = "apply" ]; then
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "configmap" ]; then
    echo '{"000001_init.up.sql":"...","000002_chat.up.sql":"...","000003_jobs.up.sql":"...","000004_receipts.up.sql":"...","000005_opt.up.sql":"...","000006_req.up.sql":"...","000007_loc.up.sql":"...","000008_e2ee.up.sql":"...","000009_auth.up.sql":"...","000010_user_recovery.up.sql":"..."}'
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "job" ]; then
    case "$*" in
        *jsonpath={.status.failed}*)
            echo "1"
            ;;
        *jsonpath={.status.active}*)
            echo "0"
            ;;
        *jsonpath={.status.succeeded}*)
            echo "0"
            ;;
        *)
            echo "easychat-db-migration"
            ;;
    esac
    exit 0
elif [ "$1" = "delete" ] && [ "$2" = "job" ]; then
    echo "ERROR: delete job called when job was failed!" >&2
    exit 99
elif [ "$1" = "logs" ]; then
    echo "FATAL: migration error at postgresql://postgres_user:secret_password_123@db.prod:5432/easychat: syntax error"
    exit 0
fi
exit 0
"""
    results.append(run_test_case(
        name="Case 6: Existing failed Job halts release, preserves Job without delete, and sanitizes logs",
        setup_fn=setup_case6,
        expected_exit_code=1,
        expected_output_substrings=[
            "An existing migration Job 'easychat-db-migration' has FAILED status",
            "Blind deletion or automatic rerun of failed migration Jobs is STRICTLY PROHIBITED",
            "postgresql://postgres_user:*****@db.prod:5432/easychat"
        ],
        forbidden_output_substrings=[
            "secret_password_123",
            "ERROR: delete job called"
        ]
    ))

    # 7. Existing ACTIVE Job causes hard stop (no overlapping execution)
    def setup_case7(test_dir, migrations_dir, k8s_dir):
        return """#!/usr/bin/env bash
if [ "$1" = "create" ] && [ "$2" = "configmap" ]; then
    exit 0
elif [ "$1" = "apply" ]; then
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "configmap" ]; then
    echo '{"000001_init.up.sql":"...","000002_chat.up.sql":"...","000003_jobs.up.sql":"...","000004_receipts.up.sql":"...","000005_opt.up.sql":"...","000006_req.up.sql":"...","000007_loc.up.sql":"...","000008_e2ee.up.sql":"...","000009_auth.up.sql":"...","000010_user_recovery.up.sql":"..."}'
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "job" ]; then
    case "$*" in
        *jsonpath={.status.active}*)
            echo "1"
            ;;
        *jsonpath={.status.failed}*)
            echo "0"
            ;;
        *jsonpath={.status.succeeded}*)
            echo "0"
            ;;
        *)
            echo "easychat-db-migration"
            ;;
    esac
    exit 0
elif [ "$1" = "delete" ] && [ "$2" = "job" ]; then
    echo "ERROR: delete job called when job was active!" >&2
    exit 99
fi
exit 0
"""
    results.append(run_test_case(
        name="Case 7: Existing active Job prevents concurrent execution and halts rollout",
        setup_fn=setup_case7,
        expected_exit_code=1,
        expected_output_substrings=[
            "An existing migration Job 'easychat-db-migration' is currently ACTIVE",
            "Concurrent or overlapping migration execution is strictly prohibited"
        ],
        forbidden_output_substrings=[
            "ERROR: delete job called"
        ]
    ))

    # 8. Existing INDETERMINATE Job causes hard stop
    def setup_case8(test_dir, migrations_dir, k8s_dir):
        return """#!/usr/bin/env bash
if [ "$1" = "create" ] && [ "$2" = "configmap" ]; then
    exit 0
elif [ "$1" = "apply" ]; then
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "configmap" ]; then
    echo '{"000001_init.up.sql":"...","000002_chat.up.sql":"...","000003_jobs.up.sql":"...","000004_receipts.up.sql":"...","000005_opt.up.sql":"...","000006_req.up.sql":"...","000007_loc.up.sql":"...","000008_e2ee.up.sql":"...","000009_auth.up.sql":"...","000010_user_recovery.up.sql":"..."}'
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "job" ]; then
    case "$*" in
        *jsonpath*)
            echo "0"
            ;;
        *)
            echo "easychat-db-migration"
            ;;
    esac
    exit 0
elif [ "$1" = "delete" ] && [ "$2" = "job" ]; then
    echo "ERROR: delete job called for indeterminate job!" >&2
    exit 99
fi
exit 0
"""
    results.append(run_test_case(
        name="Case 8: Existing indeterminate Job halts without deletion",
        setup_fn=setup_case8,
        expected_exit_code=1,
        expected_output_substrings=[
            "Existing migration Job 'easychat-db-migration' is in an indeterminate state",
            "Refusing to modify or replace Job in indeterminate state"
        ],
        forbidden_output_substrings=[
            "ERROR: delete job called"
        ]
    ))

    # 9. Existing SUCCEEDED Job pruned and replaced
    def setup_case9(test_dir, migrations_dir, k8s_dir):
        return """#!/usr/bin/env bash
if [ "$1" = "create" ] && [ "$2" = "configmap" ]; then
    exit 0
elif [ "$1" = "apply" ]; then
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "configmap" ]; then
    echo '{"000001_init.up.sql":"...","000002_chat.up.sql":"...","000003_jobs.up.sql":"...","000004_receipts.up.sql":"...","000005_opt.up.sql":"...","000006_req.up.sql":"...","000007_loc.up.sql":"...","000008_e2ee.up.sql":"...","000009_auth.up.sql":"...","000010_user_recovery.up.sql":"..."}'
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "job" ]; then
    case "$*" in
        *jsonpath={.status.succeeded}*)
            echo "1"
            ;;
        *jsonpath={.status.failed}*)
            echo "0"
            ;;
        *jsonpath={.status.active}*)
            echo "0"
            ;;
        *)
            echo "easychat-db-migration"
            ;;
    esac
    exit 0
elif [ "$1" = "delete" ] && [ "$2" = "job" ]; then
    echo "DELETE_JOB_CALLED_OK"
    exit 0
elif [ "$1" = "wait" ]; then
    exit 0
fi
exit 0
"""
    results.append(run_test_case(
        name="Case 9: Existing succeeded Job follows documented replacement path",
        setup_fn=setup_case9,
        expected_exit_code=0,
        expected_output_substrings=[
            "Existing migration Job succeeded in a prior release. Safely pruning completed Job",
            "Migration Job completed successfully. Schema is up to date"
        ]
    ))

    # 10. Job wait failure / timeout blocks rollout and sanitizes logs
    def setup_case10(test_dir, migrations_dir, k8s_dir):
        return """#!/usr/bin/env bash
if [ "$1" = "create" ] && [ "$2" = "configmap" ]; then
    exit 0
elif [ "$1" = "apply" ]; then
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "configmap" ]; then
    echo '{"000001_init.up.sql":"...","000002_chat.up.sql":"...","000003_jobs.up.sql":"...","000004_receipts.up.sql":"...","000005_opt.up.sql":"...","000006_req.up.sql":"...","000007_loc.up.sql":"...","000008_e2ee.up.sql":"...","000009_auth.up.sql":"...","000010_user_recovery.up.sql":"..."}'
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "job" ]; then
    # No existing job
    exit 1
elif [ "$1" = "wait" ]; then
    echo "timed out waiting for condition" >&2
    exit 1
elif [ "$1" = "logs" ]; then
    echo "ERROR: connection failed to postgres://app_db_user:my_db_secret@db.cluster:5432/easychat"
    exit 0
fi
exit 0
"""
    results.append(run_test_case(
        name="Case 10: Job wait failure/timeout stops workflow and sanitizes credentials in logs",
        setup_fn=setup_case10,
        expected_exit_code=1,
        expected_output_substrings=[
            "Migration Job failed to complete within",
            "Application rollout BLOCKED",
            "postgres://app_db_user:*****@db.cluster:5432/easychat"
        ],
        forbidden_output_substrings=[
            "my_db_secret"
        ]
    ))

    # 11. Golden Path (Clean execution)
    def setup_case11(test_dir, migrations_dir, k8s_dir):
        return """#!/usr/bin/env bash
if [ "$1" = "create" ] && [ "$2" = "configmap" ]; then
    exit 0
elif [ "$1" = "apply" ]; then
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "configmap" ]; then
    echo '{"000001_init.up.sql":"...","000002_chat.up.sql":"...","000003_jobs.up.sql":"...","000004_receipts.up.sql":"...","000005_opt.up.sql":"...","000006_req.up.sql":"...","000007_loc.up.sql":"...","000008_e2ee.up.sql":"...","000009_auth.up.sql":"...","000010_user_recovery.up.sql":"..."}'
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "job" ]; then
    # No job exists
    exit 1
elif [ "$1" = "wait" ]; then
    exit 0
fi
exit 0
"""
    results.append(run_test_case(
        name="Case 11: Golden Path - Clean environment, migration job applied and completes successfully",
        setup_fn=setup_case11,
        expected_exit_code=0,
        expected_output_substrings=[
            "Migration inventory check passed (all 000001-000010 up and down files verified uniquely)",
            "ConfigMap easychat-db-migrations successfully verified in namespace 'default'",
            "Migration Job completed successfully. Schema is up to date"
        ],
        forbidden_output_substrings=[
            "FATAL", "ERROR"
        ]
    ))

    # 12. Regression: Comprehensive DSN Credential Redaction (URI, unquoted KV, quoted KV, mixed-case)
    def setup_case12(test_dir, migrations_dir, k8s_dir):
        return """#!/usr/bin/env bash
if [ "$1" = "create" ] && [ "$2" = "configmap" ]; then
    exit 0
elif [ "$1" = "apply" ]; then
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "configmap" ]; then
    echo '{"000001_init.up.sql":"...","000002_chat.up.sql":"...","000003_jobs.up.sql":"...","000004_receipts.up.sql":"...","000005_opt.up.sql":"...","000006_req.up.sql":"...","000007_loc.up.sql":"...","000008_e2ee.up.sql":"...","000009_auth.up.sql":"...","000010_user_recovery.up.sql":"..."}'
    exit 0
elif [ "$1" = "get" ] && [ "$2" = "job" ]; then
    case "$*" in
        *jsonpath={.status.failed}*)
            echo "1"
            ;;
        *jsonpath={.status.active}*)
            echo "0"
            ;;
        *jsonpath={.status.succeeded}*)
            echo "0"
            ;;
        *)
            echo "easychat-db-migration"
            ;;
    esac
    exit 0
elif [ "$1" = "logs" ]; then
    echo "Line 1 URI: error at postgresql://prod_user:TEST_SECRET_123@db.prod:5432/easychat: connection refused"
    echo "Line 2 KV unquoted: failed host=db.prod port=5432 user=app_user password=TEST_SECRET_123 dbname=easychat"
    echo "Line 3 KV double-quoted: failed with password=\\"TEST_SECRET_123\\" connect_timeout=10"
    echo "Line 4 KV single-quoted: failed with password='TEST_SECRET_123' sslmode=require"
    echo "Line 5 KV mixed-case: PaSSworD=TEST_SECRET_123 host=db.prod"
    echo "Line 6 KV with parameters: user=app_admin PASSWORD=TEST_SECRET_123 application_name=easychat_migration"
    echo "Line 7 No password: connecting to host=db.prod port=5432 dbname=easychat sslmode=require (usable)"
    echo "Line 8 Multiple credentials: uri=postgresql://u1:TEST_SECRET_123@h1/db and kv password=TEST_SECRET_123 and second kv password=\\"TEST_SECRET_123\\""
    echo "Line 9 Whitespace unquoted: password  =  TEST_SECRET_123 dbname=easychat"
    echo "Line 10 Whitespace double-quoted: password = \\"TEST_SECRET_123\\" connect_timeout=10"
    echo "Line 11 Whitespace single-quoted: password  =  'TEST_SECRET_123' sslmode=require"
    exit 0
fi
exit 0
"""
    results.append(run_test_case(
        name="Case 12: Regression - Redact URI, unquoted KV, quoted KV, mixed-case, whitespace around '=', and multiple credentials per line",
        setup_fn=setup_case12,
        expected_exit_code=1,
        expected_output_substrings=[
            "postgresql://prod_user:*****@db.prod:5432/easychat",
            "password=***** dbname=easychat",
            'password="*****" connect_timeout=10',
            "password='*****' sslmode=require",
            "PaSSworD=***** host=db.prod",
            "PASSWORD=***** application_name=easychat_migration",
            "Line 7 No password: connecting to host=db.prod port=5432 dbname=easychat sslmode=require (usable)",
            'Line 8 Multiple credentials: uri=postgresql://u1:*****@h1/db and kv password=***** and second kv password="*****"',
            "Line 9 Whitespace unquoted: password  =  ***** dbname=easychat",
            'Line 10 Whitespace double-quoted: password = "*****" connect_timeout=10',
            "Line 11 Whitespace single-quoted: password  =  '*****' sslmode=require"
        ],
        forbidden_output_substrings=[
            "TEST_SECRET_123"
        ]
    ))

    print("\n========================================================")
    print("TEST SUMMARY:")
    print("========================================================")
    all_passed = True
    for i, res in enumerate(results, 1):
        status = "PASSED" if res else "FAILED"
        print(f"Test {i}: {status}")
        if not res:
            all_passed = False

    if all_passed:
        print(f"\nALL {len(results)} TEST SCENARIOS PASSED SUCCESSFULLY!")
        sys.exit(0)
    else:
        print("\nSOME TEST SCENARIOS FAILED!")
        sys.exit(1)

if __name__ == "__main__":
    main()
