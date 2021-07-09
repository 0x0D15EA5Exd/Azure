
$RessourceGroupName = ;
$server =;  ;
$storageAccountName = ;
$Container = ;
$SASToken = ;
$storageKey = ;
$BACPAC_Storage = "
$localServer = ;  
function time {
    return Get-Date -Format "MM/dd/yyyy HH:mm:ss:ff";
}
function clearStorage {
    Get-ChildItem $BACPAC_storage | Remove-Item -Recurse;
}
function clearContainer {
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey;
    $blobs = Get-AzStorageBlob -Container $Container -Context $storageContext
    foreach($blob in $blobs){
        Remove-AzStorageBlob -Blob $blob.Name -Container $Container -Context $storageContext | Out-Null;
    }
}
function checkStateV26($i) {
    $Export = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportArray[$i].OperationStatusLink;#Get state of the request on database 
    if (($Export.Status -eq "Succeeded") -and ($Export -notin $exported)) {
        #If Request = succeeded and not int Exported Array 
        #We add th request to the exported array
        $exported[$i] = $Export;
        $exportedCount = @($exported) | Measure-Object; #Count of item int the array

        if ($exportedCount.Count -eq $Databases.count) {
            #If exported array is equivalent to the number of databases return True
            return $true;
        }
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
        #Import using sqlpackage
        if ($LASTEXITCODE -ne 0) {
            Write-Host "$(time) : /!\ - Oops ran into an issue while importing $($file.Name) - /!\ ";
        }
        else {
            Write-Host "$(time) :  $($file.name) imported on local SQL Server " ; 
        }

    }
}
function export {
    
    $Databases = az sql db list --query "[? !contains(name,'---') && !contains(name,'-----')].name" -o tsv;
    $exportArray = [Object[]]::new($Databases.count);
    $exported = [Object[]]::new($Databases.Count);
    $Username =;
    $Password = Read-Host -AsSecureString "Enter password for $Username";
    
    $i = 0;
    foreach($DBName in $Databases){
        #Creation of the export request 
        $filename = $DBName +".bacpac"
        $exportArray[$i] = New-AzSqlDatabaseExport -ResourceGroupName $RessourceGroupName -ServerName $server -DatabaseName $DBName -StorageKeyType "StorageAccessKey" -StorageKey $storageKey -StorageUri "https://mtgsqlexport.blob.core.windows.net/bacpac/$filename" -AdministratorLogin $Username -AdministratorLoginPassword $Password;
        Write-Host "$(time) : Export for $DBName as started";
        $i++;
    }
    Write-Host "Please Wait "
    $n = $false; #Loop while n = False
    while ($n -eq $false) {
        for ($i = 0; $i -lt $exportArray.Count; $i++) {
            if(checkStateV26($i) -eq $true){
                #If function return true, then the export of databases is done -
                #n = True -> loop is broken -> download
                $n = $true;
            }
        }
        Start-Sleep -Seconds 2;    
    }
}

clearContainer
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew();
Write-Host "$(time) : Exporting from $server"
export;
C:\sqlpackage\azcopy.exe copy "https://-----.blob.core.windows.net/$Container/*?$SASToken"  $BACPAC_Storage; 
Write-Host "$(time) : Building databases on $localServer";
buildingOnLocalServer;
$Stopwatch.Stop();
Write-Host "$(time) : Export & Import exectued in $([math]::Round($Stopwatch.Elapsed.TotalSeconds,2))";
clearContainer;
