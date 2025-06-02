#!/bin/bash



# Detener el script si un comando falla
set -e

# --- Variables de Configuración ---
RESOURCE_GROUP="lab-escalation"
LOCATION="eastus"
IDENTITY_NAME="labidentity"
VM_NAME="compromised-vm"
VM_IMAGE="Ubuntu2204"
VM_ADMIN_USER="franklin"
VM_ADMIN_PASS="Franklin.123456" 
SP_NAME="attacker-sp"

# --- Inicio del Script ---

echo "Iniciando la configuración del laboratorio..."

echo "1. Creando el Grupo de Recursos: $RESOURCE_GROUP..."
az group create --name $RESOURCE_GROUP --location $LOCATION --output none

echo "2. Creando la Identidad Administrada: $IDENTITY_NAME..."
az identity create --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --output none

echo "3. Asignando rol 'User Access Administrator' a la Identidad..."
subscriptionId=$(az account show --query id --output tsv)
identityPrincipalId=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query principalId --output tsv)

echo "  Esperando 15 segundos para la propagación de la identidad en Azure AD..."
sleep 15

az role assignment create \
    --assignee $identityPrincipalId \
    --role "User Access Administrator" \
    --scope "/subscriptions/$subscriptionId" \
    --output none

echo "4. Creando la Máquina Virtual: $VM_NAME... (Esto puede tardar unos minutos)"
az vm create \
    --resource-group $RESOURCE_GROUP \
    --name $VM_NAME \
    --image $VM_IMAGE \
    --admin-username $VM_ADMIN_USER \
    --admin-password $VM_ADMIN_PASS \
    --assign-identity $IDENTITY_NAME \
    --output none

# --- INICIO DE LA MODIFICACIÓN ---
echo "5. Instalando herramientas (Ansible, jq, Azure CLI) en la VM..."
az vm run-command invoke \
    --resource-group $RESOURCE_GROUP \
    --name $VM_NAME \
    --command-id "RunShellScript" \
    --scripts '
        echo "--> Actualizando lista de paquetes..."
        sudo apt-get update -y
        
        echo "--> Instalando Ansible y jq..."
        sudo apt-get install -y ansible jq
        
        echo "--> Instalando Azure CLI..."
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    ' \
    --output none
# --- FIN DE LA MODIFICACIÓN ---

echo "6. Creando el Service Principal '$SP_NAME' para el atacante..."
vmId=$(az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --query id --output tsv)

# Se añade un delay antes de crear el SP para asegurar que la VM esté lista

echo "   (Esperando 10 segundos adicionales para que la VM esté completamente lista...)"
sleep 10
sp_credentials=$(az ad sp create-for-rbac --name $SP_NAME --role "Virtual Machine Contributor" --scopes $vmId)

# Extraer las credenciales del JSON a variables
appId=$(echo $sp_credentials | jq -r .appId)
password=$(echo $sp_credentials | jq -r .password)
tenant=$(echo $sp_credentials | jq -r .tenant)

echo "7. Plantando el archivo de credenciales de Ansible en la VM..."
# Usamos tee y un Here Document para crear el archivo como root dentro de la VM
az vm run-command invoke \
    --resource-group $RESOURCE_GROUP \
    --name $VM_NAME \
    --command-id "RunShellScript" \
    --scripts "sudo mkdir -p /etc/ansible && sudo tee /etc/ansible/credentials.yml > /dev/null <<EOF
# Archivo de configuración para los playbooks de Ansible
# ¡Credenciales de producción! No eliminar.
azure_app_id: $appId
azure_password: $password
azure_tenant: $tenant
EOF" \
    --output none

# --- Fin del Script ---

echo ""
echo "¡El entorno del laboratorio se ha configurado con éxito!"
echo ""
