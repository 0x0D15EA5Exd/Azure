
$RessourceGroupName = <##>;
$server = #Serveur d'origine ;
$storageAccountName = #nom du compte de stockage;
$Container = #nom du container associé au compte de stockage;
$SASToken = #token d'accès partagé;
$storageKey = #Clé du compte de stockage 
$BACPAC_Storage = #Dossier de stockage temporaire pour les .BACPAC;
$localServer = #Serveur de destination;
#Function temps : -> pour les timestamps
function time {
    return Get-Date -Format "MM/dd/yyyy HH:mm:ss:ff";
}
#Function clearStorage : Nettoyage du dossier temporaire
function clearStorage {
    Get-ChildItem $BACPAC_storage | Remove-Item -Recurse;
}
<#Funciton clearContainer : Le container est vidé après que AzCopy à téléchargé, afin d'anticiper la prochaine execution du script 
Car New-AzSqlDatabaseExport ne peut pas overwrite un container;
#>
function clearContainer {
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey;
    $blobs = Get-AzStorageBlob -Container $Container -Context $storageContext
    foreach($blob in $blobs){
        Remove-AzStorageBlob -Blob $blob.Name -Container $Container -Context $storageContext | Out-Null;
    }
}
function exportToBlobStorage {
    $Databases = az sql db list --query "[? !contains(name,'xxxxxxxx') && !contains(name,'xxxxxx')].name" -o tsv;
    #Tableau des bases de données à exporter en excluant les bases de données avec un Certificat SQL & Clé Symétrique -> export non pris en charge & de la master ;
    $Username = #pour la connexion à Azure avec AD ou ;
    $Password = Read-Host -AsSecureString "Enter password for $Username";
    foreach ($DBName in $Databases){
        $filename = $DBName + ".bacpac" ; #

        $Export = New-AzSqlDatabaseExport -ResourceGroupName $RessourceGroupName -ServerName $server -DatabaseName $DBName -StorageKeyType "StorageAccessKey" -StorageKey $storageKey -StorageUri "https://mtgsqlexport.blob.core.windows.net/bacpac/$filename" -AdministratorLogin $Username -AdministratorLoginPassword $Password;
        $ExportStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $Export.OperationStatusLink
        Write-Host "$(time) : Starting export of $DBname";
        while ($ExportStatus.Status -eq "InProgress") {
            Start-Sleep -Seconds 2;
            $ExportStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $Export.OperationStatusLink;
            Write-Host "." -NoNewline;
        }
        #Export the database to the container, with the name $filename.
        Write-Host "`r$(time) : $DBname exported to the blob storage";
    }
}
function buildingOnLocalServer{
    $files = Get-ChildItem $BACPAC_storage\*.bacpac;
    foreach($file in $files){
        sqlcmd -S $localServer -E -Q "IF EXISTS (SELECT * FROM [sys].[databases] WHERE [name] = '$([System.IO.Path]::GetFileNameWithoutExtension($file))') DROP DATABASE [$([System.IO.Path]::GetFileNameWithoutExtension($file))]" -b | Write-Host;
        ## SQLPackage can't overwrite databases -> DROP of the previous version in ordrer to reimport database;
    }
    foreach($file in $files){
        <# For each file in the directory import #>
        C:\sqlpackage\sqlpackage.exe /Action:Import /SourceFile:$file /TargetDatabaseName:$([System.IO.Path]::GetFileNameWithoutExtension($file)) /TargetServerName:$localserver | Out-Null;
        #Import using 
        if ($LASTEXITCODE -ne 0) {
            Write-Host "$(time) : /!\ - Oops ran into an issue while importing $($file.Name) - /!\ ";
        }
        else {
            Write-Host "$(time) :  $($file.name) imported on local SQL Server " ; 
        }

    }
}
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew();
exportToBlobStorage;
Write-Host "$(time) : Starting export to Azure Blob Storage.";
Write-Host "$(time) : Export to Blob Storage : DONE.";
Write-Host "$(time) : Downloading, please wait.";
C:\sqlpackage\azcopy.exe copy "https://storageAccountName.blob.core.windows.net/$Container/*?$SASToken"  $BACPAC_Storage; 
clearContainer;
Write-Host "$(time) : Starting building on local server";
buildingOnLocalServer;
clearStorage;
$Stopwatch.Stop();
Write-Host "$(time) : Export & Import done in $([math]::Round($Stopwatch.Elapsed.TotalSeconds,2)) seconds !"
