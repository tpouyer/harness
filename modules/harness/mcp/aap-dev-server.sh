#!/bin/bash
# MCP stdio server wrapping harness aap-dev make targets
# Provides 25 tools across environment, testing, sources, data, content,
# observability, and management categories.
# All tools accept optional instance_id for concurrent swarm operation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"
HARNESS_STATE_DIR="${PROJECT_ROOT}/.harness"

# Load config
[ -f "$PROJECT_ROOT/.harness/config.env" ] && source "$PROJECT_ROOT/.harness/config.env"
[ -f "$PROJECT_ROOT/.harness.local.env" ] && source "$PROJECT_ROOT/.harness.local.env"

AAP_DEV_DIR="${AAP_DEV_DIR:-${HARNESS_STATE_DIR}/aap-dev}"
AAP_VERSION="${AAP_VERSION:-2.6-next}"
AAP_DEV_BRANCH="${AAP_DEV_BRANCH:-main}"

# Resolve worktree directory for a given instance_id
resolve_worktree() {
    local instance_id="$1"
    if [ -n "$instance_id" ] && [ "$instance_id" != "null" ]; then
        echo "${HARNESS_STATE_DIR}/aap-dev-${instance_id}"
    else
        echo "$AAP_DEV_DIR"
    fi
}

# Derive port from instance_id (deterministic, in range 30000-44999)
derive_port() {
    local instance_id="$1"
    if [ -n "$instance_id" ] && [ "$instance_id" != "null" ]; then
        local hash
        hash=$(echo "$instance_id" | cksum | cut -d' ' -f1)
        echo $(( (hash % 14999) + 30000 ))
    else
        local version_port
        version_port=$(echo "$AAP_VERSION" | tr -d '.' | sed 's/-.*//')
        echo "449${version_port}"
    fi
}

# Derive cluster name from instance_id
derive_cluster() {
    local instance_id="$1"
    if [ -n "$instance_id" ] && [ "$instance_id" != "null" ]; then
        echo "kind-${instance_id}"
    else
        echo "kind-$(echo "$AAP_VERSION" | tr '.' '-')"
    fi
}

# Build env vars for concurrent instance
build_instance_env() {
    local instance_id="$1"
    local port="${2:-}"
    local cluster="${3:-}"
    local tag="${4:-}"

    if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
        echo ""
        return
    fi

    [ -z "$port" ] && port=$(derive_port "$instance_id")
    [ -z "$cluster" ] && cluster=$(derive_cluster "$instance_id")
    [ -z "$tag" ] && tag="$instance_id"

    echo "AAP_PORT=$port KIND_CLUSTER_NAME=$cluster SKAFFOLD_TAG=$tag"
}

# Get kubeconfig path for an instance
get_kubeconfig() {
    local worktree="$1"
    echo "${worktree}/tmp/kubeconfig-${AAP_VERSION}"
}

# Send JSON-RPC response
send_response() {
    local id="$1"
    local result="$2"
    printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$id" "$result"
}

# Send JSON-RPC error
send_error() {
    local id="$1"
    local code="$2"
    local message="$3"
    printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%d,"message":%s}}\n' "$id" "$code" "$(echo "$message" | jq -Rs .)"
}

# Send tool result
send_tool_result() {
    local id="$1"
    local text="$2"
    local is_error="${3:-false}"
    send_response "$id" "$(jq -n --arg text "$text" --argjson err "$is_error" '{content:[{type:"text",text:$text}],isError:$err}')"
}

# Check aap-dev is installed
check_installed() {
    local worktree="$1"
    if [ ! -d "$worktree" ]; then
        echo "AAP-Dev not installed at $worktree. Run harness/aap-dev/install first."
        return 1
    fi
    return 0
}

# Tool definitions
TOOLS_LIST=$(cat <<'TOOLS_JSON'
{
  "tools": [
    {
      "name": "aap_dev_status",
      "description": "Check if AAP is running and show pod status",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier for concurrent operation" }
        }
      }
    },
    {
      "name": "aap_dev_ensure_running",
      "description": "Deploy AAP if not running, wait for API ready. Use before any testing.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "version": { "type": "string", "description": "AAP version (default: 2.6-next)" },
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" },
          "port": { "type": "integer", "description": "AAP port (30000-44999), auto-derived from instance_id if not set" },
          "cluster_name": { "type": "string", "description": "Kind cluster name, auto-derived from instance_id if not set" },
          "skaffold_tag": { "type": "string", "description": "Image tag, auto-derived from instance_id if not set" }
        }
      }
    },
    {
      "name": "aap_dev_stop",
      "description": "Stop AAP and clean up kind cluster. Does NOT destroy shared container registry.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_url",
      "description": "Get the AAP access URL and login info",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_admin_password",
      "description": "Get the AAP admin password",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_test",
      "description": "Run ATF tests. Auto-deploys AAP if not running.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "component": { "type": "string", "description": "Component to test: controller, eda, hub, portal, platform-services, emerging-services, all" },
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_test_init",
      "description": "Initialize the ATF test suite",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_discover_tests",
      "description": "Discover existing tests covering modified code (unit + functional)",
      "inputSchema": {
        "type": "object",
        "properties": {
          "issue": { "type": "string", "description": "Jira issue key (auto-detected from branch if not set)" }
        }
      }
    },
    {
      "name": "aap_dev_commit_func_tests",
      "description": "Branch, commit, and open PR for generated functional tests in the test repo",
      "inputSchema": {
        "type": "object",
        "properties": {
          "issue": { "type": "string", "description": "Jira issue key (auto-detected from branch if not set)" }
        }
      }
    },
    {
      "name": "aap_dev_configure_sources",
      "description": "Configure custom code sources for build. Use local_path for hot-reload workflows, repo+ref for remote branches.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "sources": {
            "type": "array",
            "description": "Component sources to configure",
            "items": {
              "type": "object",
              "properties": {
                "name": { "type": "string", "description": "Component name: controller, eda, gateway, django-ansible-base" },
                "repo": { "type": "string", "description": "Git repository URL (for remote)" },
                "ref": { "type": "string", "description": "Git reference/branch (for remote)" },
                "local_path": { "type": "string", "description": "Local path to source (for hot-reload)" }
              },
              "required": ["name"]
            }
          },
          "test_repos": {
            "type": "array",
            "description": "Test repository overrides",
            "items": {
              "type": "object",
              "properties": {
                "name": { "type": "string", "description": "Test repo name" },
                "repo": { "type": "string", "description": "Git repository URL" },
                "ref": { "type": "string", "description": "Git reference/branch" }
              },
              "required": ["name"]
            }
          },
          "polling": { "type": "boolean", "description": "Enable SKAFFOLD_TRIGGER=polling (required for local paths)" },
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        },
        "required": ["sources"]
      }
    },
    {
      "name": "aap_dev_show_sources",
      "description": "Show currently configured source overrides",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_reset_sources",
      "description": "Reset sources to defaults (remove src/ overrides, use nightly images)",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_sync_status",
      "description": "Check if hot-reload file sync is active and which components support it",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_seed_default",
      "description": "Run the default data seeding playbook (creates orgs + demo workflow template)",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_seed_data",
      "description": "Seed custom data into AAP using an Ansible playbook. Pass extra_vars to override playbook variables, or playbook path for a custom seeding playbook.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" },
          "playbook": { "type": "string", "description": "Path to custom seeding playbook (default: playbooks/data-seeding/aap-dev-data-seeding.yaml)" },
          "extra_vars": { "type": "object", "description": "JSON object of extra vars to override in the playbook" }
        }
      }
    },
    {
      "name": "aap_dev_regenerate_containerfiles",
      "description": "Regenerate Containerfile definitions from upstream/nightly build definitions. Use before modifying Containerfiles to work from latest baseline.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_regenerate_k8s_manifests",
      "description": "Extract K8s manifests from a running AAP instance into manifests/base/. Requires AAP to be deployed.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_metrics_top",
      "description": "Get CPU/memory usage per pod or node. Auto-installs metrics-server if needed.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "resource": { "type": "string", "description": "Resource type: pod (default) or node", "default": "pod" },
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_observability_install",
      "description": "Install Prometheus + Grafana stack into the AAP kind cluster. Returns Grafana URL and credentials.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_observability_status",
      "description": "Check if observability stack (Prometheus + Grafana) is running. Returns pod status and Grafana URL.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_preflight",
      "description": "Check all prerequisites for aap-dev (podman, registries, tools)",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "aap_dev_logs",
      "description": "Read recent AAP logs. Use when tests fail to diagnose issues.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "lines": { "type": "integer", "description": "Number of log lines to return (default: 50)", "default": 50 },
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_events",
      "description": "Show Kubernetes events across all namespaces",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_versions",
      "description": "List available AAP versions",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "aap_dev_backup",
      "description": "Backup AAP PostgreSQL database",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_restore",
      "description": "Restore AAP PostgreSQL database from backup",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" }
        }
      }
    },
    {
      "name": "aap_dev_download_specs",
      "description": "Download OpenAPI specs from a running AAP instance. Returns JSON specs for gateway, eda, galaxy, and galaxy-pulp APIs. Use for API compatibility checking by diffing against baseline specs from aap-openapi-specs repo.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "instance_id": { "type": "string", "description": "Unique worker instance identifier" },
          "output_dir": { "type": "string", "description": "Directory to save specs (default: .harness/.cache/openapi-specs)" },
          "components": {
            "type": "array",
            "items": { "type": "string" },
            "description": "Which specs to download: gateway, eda, galaxy, galaxy-pulp (default: all)"
          }
        }
      }
    },
    {
      "name": "aap_dev_get_baseline_specs",
      "description": "Fetch baseline OpenAPI specs from the aap-openapi-specs repository (ansible-automation-platform/aap-openapi-specs). These are the canonical specs to diff against when checking for API breaking changes.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "output_dir": { "type": "string", "description": "Directory to save baseline specs (default: .harness/.cache/openapi-specs-baseline)" },
          "components": {
            "type": "array",
            "items": { "type": "string" },
            "description": "Which specs to fetch: gateway, eda, galaxy, galaxy-pulp, controller, lightspeed (default: all)"
          }
        }
      }
    }
  ]
}
TOOLS_JSON
)

# Handle tool calls
handle_tool_call() {
    local tool_name="$1"
    local arguments="$2"
    local call_id="$3"

    local instance_id
    instance_id=$(echo "$arguments" | jq -r '.instance_id // empty')

    local worktree
    worktree=$(resolve_worktree "$instance_id")

    local instance_env
    instance_env=$(build_instance_env "$instance_id" \
        "$(echo "$arguments" | jq -r '.port // empty')" \
        "$(echo "$arguments" | jq -r '.cluster_name // empty')" \
        "$(echo "$arguments" | jq -r '.skaffold_tag // empty')")

    case "$tool_name" in

        # ═══ Environment ═══

        "aap_dev_status")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local OUTPUT
            OUTPUT=$(cd "$worktree" && env $instance_env make aap-get-pods 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_ensure_running")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local version
            version=$(echo "$arguments" | jq -r '.version // "'"$AAP_VERSION"'"')
            local OUTPUT
            OUTPUT=$(cd "$worktree" && \
                env $instance_env AAP_VERSION="$version" make aap-deploy 2>&1 && \
                env $instance_env AAP_VERSION="$version" make aap-wait-up 2>&1) || true
            local port
            port=$(derive_port "$instance_id")
            OUTPUT="${OUTPUT}

AAP is ready at: http://localhost:${port}
Login: admin
Password: run aap_dev_admin_password"
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_stop")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            # Use 'clean' NOT 'really-clean' to preserve shared registry
            local OUTPUT
            OUTPUT=$(cd "$worktree" && env $instance_env make clean 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_url")
            local port
            port=$(derive_port "$instance_id")
            send_tool_result "$call_id" "AAP URL: http://localhost:${port}
Default login: admin
Password: run aap_dev_admin_password"
            ;;

        "aap_dev_admin_password")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local OUTPUT
            OUTPUT=$(cd "$worktree" && env $instance_env make admin-password 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        # ═══ Testing ═══

        "aap_dev_test")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local component
            component=$(echo "$arguments" | jq -r '.component // empty')
            local TARGET="test-atf-run"
            if [ -n "$component" ] && [ "$component" != "null" ]; then
                case "$component" in
                    controller) TARGET="test-atf-run-controller" ;;
                    eda)        TARGET="test-atf-run-eda" ;;
                    hub)        TARGET="test-atf-run-hub" ;;
                    portal)     TARGET="test-atf-run-portal" ;;
                    platform-services) TARGET="test-atf-run-ps" ;;
                    emerging-services) TARGET="test-atf-run-es" ;;
                    all)        TARGET="test-atf-run" ;;
                    *)          TARGET="test-atf-run-${component}" ;;
                esac
            fi
            local OUTPUT
            OUTPUT=$(cd "$worktree" && \
                env $instance_env AAP_VERSION="$AAP_VERSION" make "$TARGET" 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_test_init")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local OUTPUT
            OUTPUT=$(cd "$worktree" && env $instance_env make test-atf-init 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_discover_tests")
            local issue
            issue=$(echo "$arguments" | jq -r '.issue // empty')
            local OUTPUT
            OUTPUT=$(cd "$PROJECT_ROOT" && \
                HARNESS_JIRA_ISSUE="${issue:-}" \
                "$HARNESS_DIR/scripts/test-discovery.sh" 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_commit_func_tests")
            local issue
            issue=$(echo "$arguments" | jq -r '.issue // empty')
            local OUTPUT
            OUTPUT=$(cd "$PROJECT_ROOT" && \
                HARNESS_JIRA_ISSUE="${issue:-}" \
                "$HARNESS_DIR/scripts/func-test-pr.sh" 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        # ═══ Sources ═══

        "aap_dev_configure_sources")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local sources test_repos polling
            sources=$(echo "$arguments" | jq -r '.sources // []')
            test_repos=$(echo "$arguments" | jq -r '.test_repos // []')
            polling=$(echo "$arguments" | jq -r '.polling // false')

            # Build answers file
            local ANSWERS="{}"
            local CONTAINERS="[]"

            while IFS= read -r src; do
                [ -z "$src" ] && continue
                local name repo ref local_path container
                name=$(echo "$src" | jq -r '.name')
                repo=$(echo "$src" | jq -r '.repo // empty')
                ref=$(echo "$src" | jq -r '.ref // empty')
                local_path=$(echo "$src" | jq -r '.local_path // empty')

                # Map component name to container name
                case "$name" in
                    controller)           container="controller-rhel8" ;;
                    eda)                  container="eda-controller-rhel8" ;;
                    gateway)              container="gateway-rhel8" ;;
                    django-ansible-base)  container="controller-rhel8" ;;
                    *)                    container="${name}-rhel8" ;;
                esac

                CONTAINERS=$(echo "$CONTAINERS" | jq --arg c "$container" '. + [$c] | unique')

                if [ -n "$local_path" ] && [ "$local_path" != "null" ]; then
                    ANSWERS=$(echo "$ANSWERS" | jq \
                        --arg key "local-$name" --arg val "$local_path" \
                        '. + {($key): $val}')
                elif [ -n "$repo" ] && [ "$repo" != "null" ]; then
                    ANSWERS=$(echo "$ANSWERS" | jq \
                        --arg rk "repo-$name" --arg rv "$repo" \
                        --arg fk "ref-$name" --arg fv "${ref:-main}" \
                        '. + {($rk): $rv, ($fk): $fv}')
                fi
            done < <(echo "$sources" | jq -c '.[]' 2>/dev/null)

            ANSWERS=$(echo "$ANSWERS" | jq --argjson c "$CONTAINERS" '. + {containers: $c}')

            # Add test repos if specified
            if [ "$(echo "$test_repos" | jq 'length' 2>/dev/null)" -gt 0 ] 2>/dev/null; then
                local REPO_NAMES="[]"
                while IFS= read -r tr; do
                    [ -z "$tr" ] && continue
                    local tname trepo tref
                    tname=$(echo "$tr" | jq -r '.name')
                    trepo=$(echo "$tr" | jq -r '.repo // empty')
                    tref=$(echo "$tr" | jq -r '.ref // "main"')
                    REPO_NAMES=$(echo "$REPO_NAMES" | jq --arg n "$tname" '. + [$n]')
                    if [ -n "$trepo" ] && [ "$trepo" != "null" ]; then
                        ANSWERS=$(echo "$ANSWERS" | jq \
                            --arg rk "repo-$tname" --arg rv "$trepo" \
                            --arg fk "ref-$tname" --arg fv "$tref" \
                            '. + {($rk): $rv, ($fk): $fv}')
                    fi
                done < <(echo "$test_repos" | jq -c '.[]' 2>/dev/null)
                ANSWERS=$(echo "$ANSWERS" | jq --argjson r "$REPO_NAMES" '. + {repositories: $r}')
            fi

            # Write answers file and run
            local ANSWERS_FILE
            ANSWERS_FILE=$(mktemp)
            echo "$ANSWERS" > "$ANSWERS_FILE"

            local POLL_ENV=""
            if [ "$polling" = "true" ]; then
                POLL_ENV="SKAFFOLD_TRIGGER=polling"
            fi

            local OUTPUT
            OUTPUT=$(cd "$worktree" && \
                env $instance_env $POLL_ENV \
                CONFIGURATION_ANSWERS_FILE="$ANSWERS_FILE" \
                CONFIGURATION_ERROR_ON_NO_ANSWER=true \
                make configure-sources 2>&1) || true

            rm -f "$ANSWERS_FILE"
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_show_sources")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local SOURCES_FILE="${worktree}/src/${AAP_VERSION}/sources.yaml"
            if [ -f "$SOURCES_FILE" ]; then
                local OUTPUT
                OUTPUT="Current sources (${AAP_VERSION}):
$(cat "$SOURCES_FILE")"
                send_tool_result "$call_id" "$OUTPUT"
            else
                send_tool_result "$call_id" "No custom sources configured (using default nightly images)"
            fi
            ;;

        "aap_dev_reset_sources")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            rm -rf "${worktree}/src/${AAP_VERSION}"
            send_tool_result "$call_id" "Sources reset. Next deployment will use default nightly images."
            ;;

        "aap_dev_sync_status")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local SRC_DIR="${worktree}/src/${AAP_VERSION}"
            local OUTPUT="Hot-reload sync status:
"
            if [ -d "$SRC_DIR" ]; then
                OUTPUT="${OUTPUT}Source directory: ${SRC_DIR}
Components with custom sources:"
                for dir in "$SRC_DIR"/*/; do
                    [ -d "$dir" ] || continue
                    local comp
                    comp=$(basename "$dir")
                    [ "$comp" = "sources.yaml" ] && continue
                    OUTPUT="${OUTPUT}
  - ${comp}"
                done
                OUTPUT="${OUTPUT}

SKAFFOLD_TRIGGER=${SKAFFOLD_TRIGGER:-notify} (set to 'polling' for local paths)"
            else
                OUTPUT="${OUTPUT}No custom sources configured. Hot-reload is not active."
            fi
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        # ═══ Data Seeding ═══

        "aap_dev_seed_default")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local port
            port=$(derive_port "$instance_id")
            local admin_pw
            admin_pw=$(cd "$worktree" && env $instance_env make admin-password 2>&1 | tail -1)

            local OUTPUT
            OUTPUT=$(cd "$worktree" && ansible-playbook \
                playbooks/data-seeding/aap-dev-data-seeding.yaml \
                -e "aap_host=http://localhost:${port}" \
                -e "aap_admin_password=${admin_pw}" 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_seed_data")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local playbook extra_vars
            playbook=$(echo "$arguments" | jq -r '.playbook // "playbooks/data-seeding/aap-dev-data-seeding.yaml"')
            extra_vars=$(echo "$arguments" | jq -r '.extra_vars // empty')

            local port
            port=$(derive_port "$instance_id")
            local admin_pw
            admin_pw=$(cd "$worktree" && env $instance_env make admin-password 2>&1 | tail -1)

            local EXTRA_VARS_FLAG=""
            if [ -n "$extra_vars" ] && [ "$extra_vars" != "null" ]; then
                local VARS_FILE
                VARS_FILE=$(mktemp)
                echo "$extra_vars" > "$VARS_FILE"
                EXTRA_VARS_FLAG="-e @${VARS_FILE}"
            fi

            local OUTPUT
            OUTPUT=$(cd "$worktree" && ansible-playbook \
                "$playbook" \
                -e "aap_host=http://localhost:${port}" \
                -e "aap_admin_password=${admin_pw}" \
                $EXTRA_VARS_FLAG 2>&1) || true

            [ -n "${VARS_FILE:-}" ] && rm -f "$VARS_FILE"
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        # ═══ Content Regeneration ═══

        "aap_dev_regenerate_containerfiles")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local OUTPUT
            OUTPUT=$(cd "$worktree" && make regenerate-containerfiles 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_regenerate_k8s_manifests")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local kubeconfig
            kubeconfig=$(get_kubeconfig "$worktree")
            local OUTPUT
            OUTPUT=$(cd "$worktree" && \
                KUBECONFIG="$kubeconfig" \
                make regenerate-k8s-manifests 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        # ═══ Observability ═══

        "aap_dev_metrics_top")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local resource
            resource=$(echo "$arguments" | jq -r '.resource // "pod"')
            local kubeconfig
            kubeconfig=$(get_kubeconfig "$worktree")

            # Ensure metrics-server is installed
            cd "$worktree" && KUBECONFIG="$kubeconfig" make metrics-server-install 2>/dev/null || true

            local OUTPUT
            case "$resource" in
                node)
                    OUTPUT=$(KUBECONFIG="$kubeconfig" "$worktree/bin/kubectl" top node 2>&1) || true
                    ;;
                pod|*)
                    OUTPUT=$(KUBECONFIG="$kubeconfig" "$worktree/bin/kubectl" top pod --all-namespaces 2>&1) || true
                    ;;
            esac
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_observability_install")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local OUTPUT
            OUTPUT=$(cd "$worktree" && make kube-prometheus-stack-install 2>&1) || true

            # Start port-forward in background
            cd "$worktree" && make kube-prometheus-stack-port-forward &>/dev/null &

            local grafana_port=13000
            if [ -n "$instance_id" ] && [ "$instance_id" != "null" ]; then
                local hash
                hash=$(echo "$instance_id" | cksum | cut -d' ' -f1)
                grafana_port=$(( (hash % 1000) + 13000 ))
            fi

            OUTPUT="${OUTPUT}

Grafana available at: http://localhost:${grafana_port}
Credentials: admin / prom-operator

Dashboards:
  - k8s-views-global (ID: 15757)
  - k8s-views-namespaces (ID: 15758)
  - k8s-views-pods (ID: 15760)
  - k8s-views-api-server (ID: 15761)"
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_observability_status")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local kubeconfig
            kubeconfig=$(get_kubeconfig "$worktree")
            local OUTPUT
            OUTPUT=$(KUBECONFIG="$kubeconfig" \
                "$worktree/bin/kubectl" get pods -n monitoring-plus-plus 2>&1) || true

            local grafana_port=13000
            if [ -n "$instance_id" ] && [ "$instance_id" != "null" ]; then
                local hash
                hash=$(echo "$instance_id" | cksum | cut -d' ' -f1)
                grafana_port=$(( (hash % 1000) + 13000 ))
            fi

            OUTPUT="${OUTPUT}

Grafana URL: http://localhost:${grafana_port}
Credentials: admin / prom-operator"
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        # ═══ Management ═══

        "aap_dev_preflight")
            local OUTPUT
            OUTPUT=$(cd "$PROJECT_ROOT" && make harness/aap-dev/preflight 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_logs")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local lines kubeconfig
            lines=$(echo "$arguments" | jq -r '.lines // 50')
            kubeconfig=$(get_kubeconfig "$worktree")
            local OUTPUT
            OUTPUT=$(KUBECONFIG="$kubeconfig" \
                "$worktree/bin/kubectl" logs --all-containers --tail="$lines" \
                -n myaap -l app.kubernetes.io/part-of=aap 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_events")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local OUTPUT
            OUTPUT=$(cd "$worktree" && env $instance_env make aap-get-events 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_versions")
            if ! check_installed "$AAP_DEV_DIR"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $AAP_DEV_DIR" "true"
                return
            fi
            local OUTPUT
            OUTPUT=$(cd "$AAP_DEV_DIR" && make list-versions 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_backup")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local OUTPUT
            OUTPUT=$(cd "$worktree" && env $instance_env make aap-backup 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_restore")
            if ! check_installed "$worktree"; then
                send_tool_result "$call_id" "AAP-Dev not installed at $worktree" "true"
                return
            fi
            local OUTPUT
            OUTPUT=$(cd "$worktree" && env $instance_env make aap-restore 2>&1) || true
            send_tool_result "$call_id" "$OUTPUT"
            ;;

        # ═══ OpenAPI Specs ═══

        "aap_dev_download_specs")
            local port
            port=$(derive_port "$instance_id")
            local output_dir
            output_dir=$(echo "$arguments" | jq -r '.output_dir // ".harness/.cache/openapi-specs"')
            local components
            components=$(echo "$arguments" | jq -r '.components // ["gateway","eda","galaxy","galaxy-pulp"]')

            mkdir -p "$PROJECT_ROOT/$output_dir"

            # Get admin password
            local admin_pw=""
            if check_installed "$worktree" 2>/dev/null; then
                admin_pw=$(cd "$worktree" && env $instance_env make admin-password 2>&1 | tail -1)
            fi

            local OUTPUT="Downloading OpenAPI specs from http://localhost:${port}..."
            local BASE="http://localhost:${port}"

            # Spec endpoint map
            while IFS= read -r comp; do
                [ -z "$comp" ] && continue
                local endpoint="" outfile=""
                case "$comp" in
                    gateway)
                        endpoint="/api/gateway/v1/docs/schema/?format=json"
                        outfile="gateway.json"
                        ;;
                    eda)
                        endpoint="/api/eda/v1/openapi.json"
                        outfile="eda.json"
                        ;;
                    galaxy)
                        endpoint="/api/galaxy/v3/galaxy.json"
                        outfile="galaxy.json"
                        ;;
                    galaxy-pulp)
                        endpoint="/api/galaxy/v3/galaxy-pulp.json"
                        outfile="galaxy-pulp.json"
                        ;;
                    *)
                        OUTPUT="${OUTPUT}
  Skipped unknown component: $comp"
                        continue
                        ;;
                esac

                local http_code
                http_code=$(curl -s -w "%{http_code}" -o "$PROJECT_ROOT/$output_dir/$outfile" \
                    -u "admin:${admin_pw}" \
                    "${BASE}${endpoint}" 2>/dev/null || echo "000")

                if [ "$http_code" = "200" ] && [ -s "$PROJECT_ROOT/$output_dir/$outfile" ]; then
                    local size
                    size=$(du -h "$PROJECT_ROOT/$output_dir/$outfile" | cut -f1)
                    OUTPUT="${OUTPUT}
  ${comp}: OK (${size}) -> ${output_dir}/${outfile}"
                else
                    OUTPUT="${OUTPUT}
  ${comp}: FAILED (HTTP ${http_code})"
                    rm -f "$PROJECT_ROOT/$output_dir/$outfile"
                fi
            done < <(echo "$components" | jq -r '.[]' 2>/dev/null)

            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "aap_dev_get_baseline_specs")
            local output_dir
            output_dir=$(echo "$arguments" | jq -r '.output_dir // ".harness/.cache/openapi-specs-baseline"')
            local components
            components=$(echo "$arguments" | jq -r '.components // ["gateway","eda","galaxy","galaxy-pulp","controller","lightspeed"]')

            mkdir -p "$PROJECT_ROOT/$output_dir"

            local OUTPUT="Fetching baseline specs from aap-openapi-specs repo..."
            local REPO="ansible-automation-platform/aap-openapi-specs"

            while IFS= read -r comp; do
                [ -z "$comp" ] && continue
                local filename="${comp}.json"

                # Use gh CLI to fetch from repo (respects auth)
                if (unset GITHUB_TOKEN GH_TOKEN && \
                    gh api "repos/${REPO}/contents/${filename}" \
                    --jq '.content' 2>/dev/null | \
                    base64 -d > "$PROJECT_ROOT/$output_dir/$filename" 2>/dev/null) && \
                    [ -s "$PROJECT_ROOT/$output_dir/$filename" ]; then
                    local size
                    size=$(du -h "$PROJECT_ROOT/$output_dir/$filename" | cut -f1)
                    OUTPUT="${OUTPUT}
  ${comp}: OK (${size}) -> ${output_dir}/${filename}"
                else
                    OUTPUT="${OUTPUT}
  ${comp}: not found in repo (may not exist for this component)"
                    rm -f "$PROJECT_ROOT/$output_dir/$filename"
                fi
            done < <(echo "$components" | jq -r '.[]' 2>/dev/null)

            OUTPUT="${OUTPUT}

To detect breaking changes, diff baseline specs against live specs:
  baseline: ${output_dir}/
  live:     .harness/.cache/openapi-specs/ (from aap_dev_download_specs)"

            send_tool_result "$call_id" "$OUTPUT"
            ;;

        *)
            send_tool_result "$call_id" "Unknown tool: $tool_name" "true"
            ;;
    esac
}

# Main MCP protocol loop
while IFS= read -r line; do
    [ -z "$line" ] && continue

    METHOD=$(echo "$line" | jq -r '.method // empty')
    ID=$(echo "$line" | jq -r '.id // "null"')
    PARAMS=$(echo "$line" | jq -r '.params // {}')

    case "$METHOD" in
        "initialize")
            send_response "$ID" '{
                "protocolVersion": "2024-11-05",
                "capabilities": { "tools": {} },
                "serverInfo": { "name": "harness-aap-dev", "version": "1.0.0" }
            }'
            ;;

        "notifications/initialized")
            # No response needed for notifications
            ;;

        "tools/list")
            send_response "$ID" "$TOOLS_LIST"
            ;;

        "tools/call")
            TOOL_NAME=$(echo "$PARAMS" | jq -r '.name')
            ARGUMENTS=$(echo "$PARAMS" | jq -r '.arguments // {}')
            handle_tool_call "$TOOL_NAME" "$ARGUMENTS" "$ID"
            ;;

        *)
            if [ "$ID" != "null" ]; then
                send_error "$ID" -32601 "Method not found: $METHOD"
            fi
            ;;
    esac
done
