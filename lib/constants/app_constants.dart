class AppConstants {
  // API Configuration
  static const String baseUrl = 'https://api.alignsys.tech';
  static const String apiPath = '/api';
  
  // Endpoints
  static const String getVaultObjectTypes =
    '$apiPath/MfilesObjects/GetVaultsObjects/{vaultGuid}/{userId}';

  static const String getObjectClasses =
    '$apiPath/MfilesObjects/GetObjectClasses/{vaultGuid}/{objectTypeId}/{userId}';

  static const String getClassProps =
    '$apiPath/MfilesObjects/ClassProps/{vaultGuid}/{objectTypeId}/{classId}/{userId}';

  static const String postFileUploadAsync = 
    '$apiPath/objectinstance/FilesUploadAsync';

  static const String postObjectCreation = 
    '$apiPath/objectinstance/ObjectCreation';
  
  // Data Types
  /*
  static const int dataTypeText = 1;
  static const int dataTypeInteger = 2;
  static const int dataTypeDecimal = 3;
  static const int dataTypeDate = 5;
  static const int dataTypeTime = 6;
  static const int dataTypeDateTime = 7;
  static const int dataTypeBoolean = 8;
  static const int dataTypeLookup = 9;
  static const int dataTypeMultiLookup = 10;
  static const int dataTypeMultiLineText = 13;
  */
  
  // UI Constants
  static const double defaultPadding = 16.0;
  static const double cardMargin = 8.0;
  static const double iconSize = 24.0;
  static const double errorIconSize = 64.0;
  
  // Messages
  static const String loadingMessage = 'Loading...';
  static const String noDataMessage = 'No data available';
  static const String errorTitle = 'Error';
  static const String successTitle = 'Success';
  static const String objectCreatedMessage = 'Object created successfully!';
  static const String fileUploadFailedMessage = 'Failed to upload file';
  static const String objectCreationFailedMessage = 'Failed to create object';
  static const String selectFileMessage = 'Please select a file for document objects';
  static const String retryButtonText = 'Retry';
  static const String createButtonText = 'Create Object';
  static const String selectFileButtonText = 'Select File';
  static const String noFileSelectedText = 'No file selected';
  static const String automaticFieldText = 'Automatic';
}