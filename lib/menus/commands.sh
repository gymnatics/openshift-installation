#!/bin/bash
################################################################################
# Command Registry — flat command mode for rhoai-toolkit.sh
# Allows: ./rhoai-toolkit.sh <command> [subcommand] [args]
# Bypasses the interactive menu system entirely.
################################################################################

_COMMANDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

show_commands_help() {
    echo ""
    echo -e "${CYAN}Available commands:${NC}"
    echo ""
    echo -e "${MAGENTA}Installation:${NC}"
    echo "  install rhoai-35              Full RHOAI 3.5 install (recommended)"
    echo "  install rhoai-34              Full RHOAI 3.4 install"
    echo "  install rhoai-33              Full RHOAI 3.3 install"
    echo "  install minimal               Minimal RHOAI (choose operators)"
    echo ""
    echo -e "${MAGENTA}Model Management:${NC}"
    echo "  deploy model                  Interactive model deployment"
    echo "  deploy model <name> <source>  Deploy model directly"
    echo "  serve model                   Alias for deploy model"
    echo ""
    echo -e "${MAGENTA}Demos:${NC}"
    echo "  deploy demo environment       Deploy full demo environment"
    echo "  deploy demo banking           Banking Demo (Feast)"
    echo "  deploy demo webui             Open WebUI"
    echo "  deploy demo llamastack        LlamaStack Demo"
    echo "  deploy demo guidellm          GuideLLM benchmarking"
    echo "  deploy demo guardrails        NeMo Guardrails Demo"
    echo "  deploy demo n8n               n8n workflow automation"
    echo "  deploy demo lmeval            LMEval Builder Lab"
    echo "  deploy demo maas-ratelimit    MaaS rate limiting test"
    echo "  deploy demo pipeline          AI Pipeline Demo"
    echo "  deploy demo financial-loan    Financial Loan Demo"
    echo "  deploy demo autorag           AutoRAG Demo (TP)"
    echo ""
    echo -e "${MAGENTA}MaaS & Services:${NC}"
    echo "  setup maas                    Setup MaaS (version-aware)"
    echo "  setup llamastack              Deploy LlamaStack"
    echo "  setup model-registry          Deploy Model Registry"
    echo "  setup pipeline-server         Deploy Pipeline Server"
    echo "  setup feast                   Feature Store management"
    echo ""
    echo -e "${MAGENTA}GPU & Hardware:${NC}"
    echo "  create gpu-machineset         Create GPU MachineSet on AWS"
    echo "  create hardware-profile       Create GPU Hardware Profile"
    echo ""
    echo -e "${MAGENTA}Configuration:${NC}"
    echo "  enable dashboard-features     Enable dashboard features"
    echo "  enable dashboard <feature>    Enable specific feature"
    echo ""
    echo -e "${MAGENTA}Troubleshooting:${NC}"
    echo "  fix gpu-operator              Fix GPU Operator CUDA compat"
    echo "  fix operators                 Re-sync operator channels"
    echo "  status operators              Check all operator status"
    echo "  status gpu                    Check GPU operator status"
    echo ""
    echo -e "${MAGENTA}Utilities:${NC}"
    echo "  help                          Show this help"
    echo "  menu                          Enter interactive menu mode"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  ./rhoai-toolkit.sh deploy demo webui"
    echo "  ./rhoai-toolkit.sh install rhoai-35 --skip-prerequisites"
    echo "  ./rhoai-toolkit.sh setup maas"
    echo ""
}

# Route a command to the appropriate handler function
route_command() {
    local cmd="${1:-}"
    local subcmd="${2:-}"
    shift 2 2>/dev/null || true

    case "$cmd" in
        help|--help|-h)
            show_commands_help
            return 0
            ;;
        menu|"")
            return 1  # Signals caller to enter interactive mode
            ;;
        install)
            case "$subcmd" in
                rhoai-35|rhoai35|35)
                    exec "$_COMMANDS_DIR/scripts/install-rhoai-35.sh" "$@"
                    ;;
                rhoai-34|rhoai34|34)
                    exec "$_COMMANDS_DIR/scripts/install-rhoai-34.sh" "$@"
                    ;;
                rhoai-33|rhoai33|33)
                    exec "$_COMMANDS_DIR/scripts/install-rhoai-33.sh" "$@"
                    ;;
                minimal)
                    exec "$_COMMANDS_DIR/scripts/install-rhoai-minimal.sh" "$@"
                    ;;
                *)
                    print_error "Unknown install target: $subcmd"
                    echo "Available: rhoai-35, rhoai-34, rhoai-33, minimal"
                    return 1
                    ;;
            esac
            ;;
        deploy)
            case "$subcmd" in
                model|serve)
                    exec "$_COMMANDS_DIR/scripts/serve-model.sh" "$@"
                    ;;
                demo)
                    route_demo_command "$@"
                    ;;
                dashboards)
                    exec "$_COMMANDS_DIR/scripts/deploy-dashboards.sh" "${@:3}"
                    ;;
                *)
                    print_error "Unknown deploy target: $subcmd"
                    echo "Available: model, demo <name>, dashboards"
                    return 1
                    ;;
            esac
            ;;
        serve)
            exec "$_COMMANDS_DIR/scripts/serve-model.sh" "$subcmd" "$@"
            ;;
        setup)
            case "$subcmd" in
                maas)
                    exec "$_COMMANDS_DIR/scripts/setup-maas.sh" "$@"
                    ;;
                llamastack)
                    exec "$_COMMANDS_DIR/scripts/setup-llamastack.sh" "$@" 2>/dev/null || \
                        print_error "setup-llamastack.sh not found"
                    ;;
                model-registry|registry)
                    setup_model_registry "$@"
                    ;;
                pipeline-server|pipelines)
                    setup_pipeline_server "$@"
                    ;;
                feast|feature-store)
                    feast_submenu
                    ;;
                *)
                    print_error "Unknown setup target: $subcmd"
                    echo "Available: maas, llamastack, model-registry, pipeline-server, feast"
                    return 1
                    ;;
            esac
            ;;
        create)
            case "$subcmd" in
                gpu-machineset|gpu)
                    exec "$_COMMANDS_DIR/scripts/create-gpu-machineset.sh" "$@"
                    ;;
                hardware-profile|hwprofile)
                    exec "$_COMMANDS_DIR/scripts/create-hardware-profile.sh" "$@"
                    ;;
                *)
                    print_error "Unknown create target: $subcmd"
                    echo "Available: gpu-machineset, hardware-profile"
                    return 1
                    ;;
            esac
            ;;
        enable)
            case "$subcmd" in
                dashboard-features|dashboard)
                    exec "$_COMMANDS_DIR/scripts/enable-dashboard-features.sh" "$@"
                    ;;
                *)
                    print_error "Unknown enable target: $subcmd"
                    echo "Available: dashboard-features"
                    return 1
                    ;;
            esac
            ;;
        fix)
            case "$subcmd" in
                gpu-operator|gpu)
                    fix_gpu_operator_cuda_compatibility
                    ;;
                operators)
                    print_warning "fix operators: not yet implemented"
                    ;;
                *)
                    print_error "Unknown fix target: $subcmd"
                    echo "Available: gpu-operator, operators"
                    return 1
                    ;;
            esac
            ;;
        status)
            case "$subcmd" in
                operators|ops)
                    check_all_operator_status
                    ;;
                gpu)
                    check_gpu_operator_status
                    ;;
                *)
                    print_error "Unknown status target: $subcmd"
                    echo "Available: operators, gpu"
                    return 1
                    ;;
            esac
            ;;
        *)
            print_error "Unknown command: $cmd"
            show_commands_help
            return 1
            ;;
    esac
}

route_demo_command() {
    local demo_name="${1:-}"
    shift 2>/dev/null || true

    case "$demo_name" in
        environment|all)
            exec "$_COMMANDS_DIR/scripts/deploy-demo-environment.sh" "$@"
            ;;
        banking|feast)
            exec "$_COMMANDS_DIR/demo/feast-demo/deploy.sh" "$@" 2>/dev/null || \
                print_error "Banking demo deploy.sh not found"
            ;;
        webui|open-webui)
            deploy_open_webui "$@"
            ;;
        llamastack)
            exec "$_COMMANDS_DIR/demo/llamastack-demo/deploy.sh" "$@" 2>/dev/null || \
                print_error "LlamaStack demo deploy.sh not found"
            ;;
        guidellm)
            deploy_guidellm "$@"
            ;;
        guardrails|nemo-guardrails)
            exec "$_COMMANDS_DIR/demo/nemo-guardrails-demo/deploy.sh" "$@" 2>/dev/null || \
                print_error "NeMo Guardrails demo deploy.sh not found"
            ;;
        n8n)
            exec "$_COMMANDS_DIR/demo/n8n-demo/deploy.sh" "$@"
            ;;
        lmeval|lm-eval)
            exec "$_COMMANDS_DIR/demo/lmeval-demo/deploy.sh" "$@"
            ;;
        maas-ratelimit|ratelimit)
            exec "$_COMMANDS_DIR/demo/maas-ratelimit-demo/deploy.sh" "$@"
            ;;
        pipeline|pipelines)
            exec "$_COMMANDS_DIR/demo/pipeline-demo/deploy.sh" "$@"
            ;;
        financial-loan|loan)
            exec "$_COMMANDS_DIR/demo/financial-loan-demo/deploy.sh" "$@"
            ;;
        autorag)
            exec "$_COMMANDS_DIR/demo/autorag-demo/deploy.sh" "$@"
            ;;
        lemonade|lemonade-stand)
            exec "$_COMMANDS_DIR/demo/lemonade-stand-demo/deploy.sh" "$@"
            ;;
        mlflow-tracing|mlflow)
            bash "$_COMMANDS_DIR/demo/mlflow-tracing-demo/deploy.sh"
            ;;
        lightspeed)
            bash "$_COMMANDS_DIR/demo/lightspeed-demo/deploy.sh" deploy
            ;;
        "")
            print_error "Demo name required"
            echo "Available: environment, banking, webui, llamastack, guidellm, guardrails,"
            echo "           n8n, lmeval, maas-ratelimit, pipeline, financial-loan, autorag"
            return 1
            ;;
        *)
            print_error "Unknown demo: $demo_name"
            echo "Available: environment, banking, webui, llamastack, guidellm, guardrails,"
            echo "           n8n, lmeval, maas-ratelimit, pipeline, financial-loan, autorag"
            return 1
            ;;
    esac
}
