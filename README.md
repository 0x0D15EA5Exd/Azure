# Azure : SQL Automation - Export & Import 





Automatisation de l'export des bases de données depuis Azure SQL Server vers un fichier .BACPAC dans un stockage stokcage Blob.
  - New-AzSqlDatabaseExport -> Export;
  - Get-AzSqlDatabaseImportExportStatus -> Boucle pour vérifier l'état des exports;
  - AzCopy -> Téléchargement du conteneur;

Automatisation de l'import des bases de données sur SQL Express 
  - SQL Package -> Import les bases de données;
  - sqlcmd -> DROP version précédente des BDDs;
