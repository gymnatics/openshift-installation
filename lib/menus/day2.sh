#!/bin/bash
################################################################################
# day2.sh — Day 2 Operations submenu
# Extracted from rhoai-toolkit.sh
################################################################################

_DAY2_MENU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

day2_operations_submenu() {
    while true; do
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                 Day 2 Operations                               ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}1)${NC} Approve Pending CSRs"
        echo "    Approve certificate signing requests for new/rebooted nodes"
        echo ""
        echo -e "${YELLOW}2)${NC} Remove kubeadmin ${RED}[Destructive]${NC}"
        echo "    Permanently remove the kubeadmin user (requires htpasswd admin)"
        echo ""
        echo -e "${YELLOW}3)${NC} Recover Ingress Router"
        echo "    Fix router pod stuck in CrashLoopBackOff"
        echo ""
        echo -e "${YELLOW}0)${NC} Back"
        echo ""

        read -p "Select an option (0-3): " day2_choice
        case $day2_choice in
            1)
                approve_pending_csrs
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                remove_kubeadmin
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                print_header "Router Recovery"
                source "$_DAY2_MENU_DIR/scripts/install-rhoai-35.sh" --source-only 2>/dev/null || true
                local router_status
                router_status=$(oc get pods -n openshift-ingress \
                    -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default \
                    -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
                if [ "$router_status" = "CrashLoopBackOff" ]; then
                    print_warning "Router is in CrashLoopBackOff — restarting..."
                    oc delete pod -n openshift-ingress \
                        -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default \
                        --wait=false 2>/dev/null
                    sleep 10
                    oc get pods -n openshift-ingress --no-headers
                    print_success "Router pod restarted"
                else
                    local phase
                    phase=$(oc get pods -n openshift-ingress \
                        -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default \
                        -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
                    print_success "Router is healthy (status: $phase)"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            0)
                return 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}
