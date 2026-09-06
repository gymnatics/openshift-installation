#!/bin/bash
################################################################################
# install.sh — RHOAI installation menus (version selection, 2.x installer)
# Extracted from rhoai-toolkit.sh
################################################################################

_INSTALL_MENU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

################################################################################
# Unified RHOAI Installation (dynamic channel selection)
################################################################################

install_rhoai_menu() {
    print_header "Install Red Hat OpenShift AI"

    print_step "Fetching available RHOAI channels from cluster..."

    local channel_data
    channel_data=$(oc get packagemanifest rhods-operator -n openshift-marketplace \
        -o jsonpath='{range .status.channels[*]}{.name}|{.currentCSV}{"\n"}{end}' 2>/dev/null)

    if [ -z "$channel_data" ]; then
        print_error "Unable to fetch RHOAI channels from cluster"
        print_info "Make sure you are connected to an OpenShift cluster with access to redhat-operators"
        echo ""
        read -p "Press Enter to return to main menu..."
        return 1
    fi

    local default_channel
    default_channel=$(oc get packagemanifest rhods-operator -n openshift-marketplace \
        -o jsonpath='{.status.defaultChannel}' 2>/dev/null)

    local -a channel_list
    local -a channel_versions
    while IFS='|' read -r ch_name ch_csv; do
        [ -z "$ch_name" ] && continue
        local ver="${ch_csv##*.}"
        if [[ "$ch_csv" =~ ([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
            ver="${BASH_REMATCH[1]}"
        fi
        channel_list+=("$ch_name")
        channel_versions+=("$ver")
    done < <(echo "$channel_data" | sort -t'|' -k2 -rV)

    echo ""
    echo -e "${CYAN}Available RHOAI channels on this cluster:${NC}"
    echo ""
    local i=1
    for idx in "${!channel_list[@]}"; do
        local ch="${channel_list[$idx]}"
        local ver="${channel_versions[$idx]}"
        local label=""
        if [ "$ch" = "$default_channel" ]; then
            label=" ${GREEN}[default]${NC}"
        fi
        printf "  ${YELLOW}%d)${NC} %-16s — v%s%b\n" "$i" "$ch" "$ver" "$label"
        i=$((i + 1))
    done
    echo ""
    echo -e "  ${YELLOW}0)${NC} Back to main menu"
    echo ""

    read -p "Select channel (1-${#channel_list[@]}, 0): " ch_choice

    if [ "$ch_choice" = "0" ] || [ -z "$ch_choice" ]; then
        return 0
    fi

    if ! [[ "$ch_choice" =~ ^[0-9]+$ ]] || [ "$ch_choice" -lt 1 ] || [ "$ch_choice" -gt "${#channel_list[@]}" ]; then
        print_warning "Invalid selection"
        echo ""
        read -p "Press Enter to return to main menu..."
        return 0
    fi

    local selected_channel="${channel_list[$((ch_choice - 1))]}"
    echo ""
    print_info "Selected channel: $selected_channel"
    echo ""

    case "$selected_channel" in
        *3.5*|fast-3.x|stable-3.x)
            echo -e "${CYAN}Launching RHOAI 3.5 installer (channel: $selected_channel)...${NC}"
            echo ""
            read -p "Proceed? (Y/n): " confirm
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                "$SCRIPT_DIR/scripts/install-rhoai-35.sh" --channel "$selected_channel"
            fi
            ;;
        *3.4*)
            echo -e "${CYAN}Launching RHOAI 3.4 installer (channel: $selected_channel)...${NC}"
            echo ""
            read -p "Proceed? (Y/n): " confirm
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                "$SCRIPT_DIR/scripts/install-rhoai-34.sh" --channel "$selected_channel"
            fi
            ;;
        *3.3*)
            echo -e "${CYAN}Launching RHOAI 3.3 installer (channel: $selected_channel)...${NC}"
            echo ""
            read -p "Proceed? (Y/n): " confirm
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                "$SCRIPT_DIR/scripts/install-rhoai-33.sh" --channel "$selected_channel"
            fi
            ;;
        stable-2.*|stable)
            local version="${selected_channel#stable-}"
            [ "$version" = "stable" ] && version="2.25"
            echo -e "${CYAN}Launching RHOAI 2.x installer (version $version)...${NC}"
            echo ""
            read -p "Proceed? (Y/n): " confirm
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                install_rhoai_2x "$version" "$selected_channel"
            fi
            ;;
        *)
            print_info "No dedicated installer for channel '$selected_channel'"
            print_info "Using interactive operator installer..."
            echo ""
            read -p "Proceed? (Y/n): " confirm
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                SELECTED_RHOAI_CHANNEL="$selected_channel"
                install_rhoai_operator_interactive
            fi
            ;;
    esac

    echo ""
    read -p "Press Enter to return to main menu..."
}

################################################################################
# RHOAI 2.x Installation (Older Versions)
################################################################################

show_rhoai_2x_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           RHOAI 2.x Installation (Older Versions)              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Note:${NC} RHOAI 2.x uses different APIs and dependencies than 3.x"
    echo ""
    echo -e "${YELLOW}1)${NC} Install RHOAI 2.25 (Latest 2.x) ${GREEN}[Recommended]${NC}"
    echo "    Channel: stable-2.25"
    echo ""
    echo -e "${YELLOW}2)${NC} Install RHOAI 2.22"
    echo "    Channel: stable-2.22"
    echo ""
    echo -e "${YELLOW}3)${NC} Install RHOAI 2.19"
    echo "    Channel: stable-2.19"
    echo ""
    echo -e "${YELLOW}4)${NC} Check Current RHOAI Version"
    echo ""
    echo -e "${YELLOW}0)${NC} Back to Main Menu"
    echo ""
}

install_rhoai_2x() {
    local version="$1"
    local channel="$2"
    
    print_header "Installing RHOAI $version (Channel: $channel)"
    
    local manifests_dir="$SCRIPT_DIR/lib/manifests/rhoai-2x"
    
    if [ ! -d "$manifests_dir" ]; then
        print_error "RHOAI 2.x manifests not found at: $manifests_dir"
        return 1
    fi
    
    # Step 1: Install NFD Operator
    print_step "Installing Node Feature Discovery (NFD) Operator..."
    if oc get subscription nfd -n openshift-nfd &>/dev/null; then
        print_success "NFD Operator already installed"
    else
        oc apply -f "$manifests_dir/nfd.yaml"
        print_success "NFD Operator subscription created"
    fi
    
    print_step "Waiting for NFD CRD..."
    local timeout=120
    local elapsed=0
    until oc get crd nodefeaturediscoveries.nfd.openshift.io &>/dev/null; do
        if [ $elapsed -ge $timeout ]; then
            print_warning "Timeout waiting for NFD CRD, continuing..."
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    if oc get crd nodefeaturediscoveries.nfd.openshift.io &>/dev/null; then
        print_step "Creating NFD instance..."
        oc apply -f "$manifests_dir/nfd-cr.yaml" || true
        print_success "NFD instance created"
    fi
    
    # Step 2: Install NVIDIA GPU Operator
    print_step "Installing NVIDIA GPU Operator..."
    if oc get subscription gpu-operator-certified -n nvidia-gpu-operator &>/dev/null; then
        print_success "GPU Operator already installed"
    else
        oc apply -f "$manifests_dir/nvidia.yaml"
        print_success "GPU Operator subscription created (Automatic approval)"
    fi
    
    print_step "Waiting for ClusterPolicy CRD..."
    timeout=180
    elapsed=0
    until oc get crd clusterpolicies.nvidia.com &>/dev/null; do
        if [ $elapsed -ge $timeout ]; then
            print_warning "Timeout waiting for GPU Operator CRD, continuing..."
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if oc get crd clusterpolicies.nvidia.com &>/dev/null; then
        print_step "Creating ClusterPolicy..."
        oc apply -f "$manifests_dir/nvidia-cr.yaml" || true
        print_success "ClusterPolicy created"
    fi
    
    # Step 3: Install dependency operators
    print_step "Installing Authorino Operator..."
    oc apply -f "$manifests_dir/authorino.yaml" || true
    
    print_step "Installing Serverless Operator..."
    oc apply -f "$manifests_dir/serverless.yaml" || true
    
    print_step "Installing Service Mesh Operator..."
    oc apply -f "$manifests_dir/servicemesh.yaml" || true
    
    # Step 4: Install RHOAI Operator with specified channel
    print_step "Installing RHOAI Operator (channel: $channel)..."
    
    local template="$_INSTALL_MENU_DIR/lib/manifests/rhoai-2x/rhoai-operator.yaml.tmpl"
    if [ -f "$template" ]; then
        export CHANNEL="$channel"
        envsubst < "$template" | oc apply -f -
        unset CHANNEL
    else
        print_warning "Template not found, falling back to static manifest..."
        oc apply -f "$manifests_dir/rhoai.yaml"
    fi
    
    print_success "RHOAI Operator subscription created"
    
    # Wait for DSCInitialization
    print_step "Waiting for RHOAI Operator to initialize (this may take 2-3 minutes)..."
    timeout=300
    elapsed=0
    until oc get DSCInitialization/default-dsci -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q "True"; do
        if [ $elapsed -ge $timeout ]; then
            print_warning "Timeout waiting for DSCInitialization"
            break
        fi
        echo "  Waiting for DSCInitialization... (${elapsed}s elapsed)"
        sleep 15
        elapsed=$((elapsed + 15))
    done
    
    if oc get DSCInitialization/default-dsci -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q "True"; then
        print_success "DSCInitialization is ready"
    fi
    
    # Step 5: Create DataScienceCluster
    print_step "Creating DataScienceCluster..."
    oc apply -f "$manifests_dir/datasciencecluster.yaml"
    
    print_step "Waiting for DataScienceCluster to be ready..."
    timeout=600
    elapsed=0
    until oc get DataScienceCluster/default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; do
        if [ $elapsed -ge $timeout ]; then
            print_warning "Timeout waiting for DataScienceCluster"
            break
        fi
        echo "  Waiting for DataScienceCluster... (${elapsed}s elapsed)"
        sleep 15
        elapsed=$((elapsed + 15))
    done
    
    if oc get DataScienceCluster/default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        print_success "DataScienceCluster is ready"
    fi
    
    # Step 6: Set operator to manual upgrades
    print_step "Setting RHOAI operator to manual upgrades..."
    oc patch subscription rhods-operator -n redhat-ods-operator --type=merge -p '{"spec": {"installPlanApproval": "Manual"}}' || true
    
    # Step 7: Apply additional configurations
    print_step "Applying dashboard configuration..."
    oc apply -f "$manifests_dir/odhdashboardconfig.yaml" || true
    
    print_step "Creating admin group with kube:admin..."
    oc apply -f "$manifests_dir/group.yaml" || true
    
    print_step "Configuring RHOAI dashboard admin groups..."
    oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{
      "spec": {
        "groupsConfig": {
          "adminGroups": "rhods-admins,dedicated-admins,cluster-admins",
          "allowedGroups": "system:authenticated"
        }
      }
    }' 2>/dev/null || true
    
    print_step "Creating serving runtime template..."
    oc apply -f "$manifests_dir/template-rhaiis.yaml" || true
    
    print_step "Creating GPU hardware profile..."
    oc apply -f "$manifests_dir/hardwareprofile.yaml" || true
    
    print_step "Enabling user workload monitoring..."
    oc apply -f "$manifests_dir/uwm.yaml" || true
    
    print_step "Restarting dashboard pods..."
    oc delete pods -l app=rhods-dashboard -n redhat-ods-applications 2>/dev/null || true
    sleep 5
    
    # Display summary
    echo ""
    print_header "RHOAI $version Installation Summary"
    
    local installed_version=$(oc get csv -n redhat-ods-operator 2>/dev/null | grep rhods | awk '{print $2}' || echo "Unknown")
    local dsc_status=$(oc get DataScienceCluster/default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    local dashboard_url=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "Not available")
    
    echo -e "${GREEN}Installed Version:${NC} $installed_version"
    echo -e "${GREEN}DSC Status:${NC} $dsc_status"
    echo -e "${GREEN}Dashboard URL:${NC} $dashboard_url"
    echo ""
    
    print_step "Installed Components:"
    oc get DataScienceCluster/default-dsc -o jsonpath='{.status.installedComponents}' 2>/dev/null | jq . || true
    
    print_success "RHOAI $version installation complete!"
    return 0
}

check_rhoai_version() {
    print_header "Current RHOAI Installation"
    
    echo -e "${CYAN}Checking RHOAI operator...${NC}"
    echo ""
    
    local csv_info=$(oc get csv -n redhat-ods-operator 2>/dev/null | grep rhods || true)
    
    if [ -z "$csv_info" ]; then
        print_warning "RHOAI is not installed on this cluster"
        return 0
    fi
    
    echo -e "${GREEN}Operator:${NC}"
    echo "$csv_info"
    echo ""
    
    local subscription_channel=$(oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.spec.channel}' 2>/dev/null || echo "Unknown")
    echo -e "${GREEN}Subscription Channel:${NC} $subscription_channel"
    echo ""
    
    local dsc_status=$(oc get DataScienceCluster/default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Not found")
    echo -e "${GREEN}DataScienceCluster Status:${NC} $dsc_status"
    echo ""
    
    echo -e "${GREEN}Installed Components:${NC}"
    oc get DataScienceCluster/default-dsc -o jsonpath='{.status.installedComponents}' 2>/dev/null | jq . || echo "  Not available"
    echo ""
    
    local dashboard_url=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "Not available")
    echo -e "${GREEN}Dashboard URL:${NC} $dashboard_url"
    
    return 0
}

rhoai_2x_menu() {
    while true; do
        show_rhoai_2x_menu
        read -p "Select an option (0-4): " choice
        
        case $choice in
            1)
                install_rhoai_2x "2.25" "stable-2.25"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                install_rhoai_2x "2.22" "stable-2.22"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                install_rhoai_2x "2.19" "stable-2.19"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                check_rhoai_version
                echo ""
                read -p "Press Enter to continue..."
                ;;
            0)
                return 0
                ;;
            *)
                print_warning "Invalid option. Please try again."
                sleep 1
                ;;
        esac
    done
}

run_maas_only_setup() {
    print_header "MaaS Setup Only"
    
    echo -e "${YELLOW}This will set up MaaS API infrastructure.${NC}"
    echo -e "${YELLOW}Assumes RHOAI is already installed.${NC}"
    echo ""
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Setup cancelled by user"
        return 0
    fi
    
    echo ""
    
    if run_maas_setup; then
        print_success "MaaS setup completed successfully"
    else
        print_error "MaaS setup failed"
        return 1
    fi
    
    return 0
}
