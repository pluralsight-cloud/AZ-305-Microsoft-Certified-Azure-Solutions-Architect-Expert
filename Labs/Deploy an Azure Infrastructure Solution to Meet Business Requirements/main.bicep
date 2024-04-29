var location = resourceGroup().location
var uniqueString = toLower(substring(replace(resourceGroup().name, '-', ''), 0, 5 ))
var aspName = 'asp-imageresizer${uniqueString}'
var webAppName = 'app-imageresizer${uniqueString}'
var storageAccountName = 'stimageresize${uniqueString}'
var azureFunctionName = 'func-${uniqueString}'
var eventGridTopicName = 'evgt-${uniqueString}'
var eventGridSubscriptionName = 'egst-${uniqueString}'
var gitRepoUrl = 'https://github.com/WayneHoggett-ACG/storage-blob-upload-from-webapp'
var functionGitRepoUrl = 'https://github.com/WayneHoggett-ACG/function-image-upload-resize'

resource appServicePlan 'Microsoft.Web/serverfarms@2020-12-01' = {
  name: aspName
  location: location
  sku: {
    name: 'B1'
    capacity: 1
  }
}

resource webApplication 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: false
    siteConfig: {
      appSettings:[
        {
          name: 'AzureStorageConfig__AccountName'
          value: storageaccount.name
        }
        {
          name: 'AzureStorageConfig__AccountKey'
          value: storageaccount.listKeys().keys[0].value
        }
        {
          name: 'AzureStorageConfig__ImageContainer'
          value: 'images'
        }
        {
          name: 'AzureStorageConfig__ThumbnailContainer'
          value: 'thumbnails'
        }
      ]
    }
  }
}

resource webappgitsource 'Microsoft.Web/sites/sourcecontrols@2021-01-01' = {
  parent: webApplication
  name: 'web'
  properties: {
    repoUrl: gitRepoUrl
    branch: 'master'
    isManualIntegration: true
  }
}

resource storageaccount 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: false
    allowBlobPublicAccess: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storageaccount
}

resource imagescontainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'images'
  parent: blobService
  properties: {
    publicAccess: 'Container'
  }
}

resource thumbnailscontainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'thumbnails'
  parent: blobService
  properties: {
    publicAccess: 'Container'
  }
}

resource azureFunction 'Microsoft.Web/sites@2020-12-01' = {
  name: azureFunctionName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: false
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageaccount.name};AccountKey=${storageaccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~2'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'THUMBNAIL_CONTAINER_NAME'
          value: 'thumbnails'
        }
        {
          name: 'THUMBNAIL_WIDTH'
          value: '100'
        }
        {
          name: 'datatype'
          value: 'binary'
        }
      ]
    }
  }
}

resource functionappgitsource 'Microsoft.Web/sites/sourcecontrols@2021-01-01' = {
  parent: azureFunction
  name: 'web'
  properties: {
    repoUrl: functionGitRepoUrl
    branch: 'master'
    isManualIntegration: true
  }
}

resource eventgridsystemtopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  dependsOn: [
    azureFunction
    functionappgitsource
  ]
  properties: {
    source: storageaccount.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

resource eventsubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
  name: eventGridSubscriptionName
  parent: eventgridsystemtopic
  dependsOn: [
    functionappgitsource 
  ]
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${azureFunction.id}/functions/Thumbnail'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      subjectBeginsWith: '/blobservices/default/containers/images/'
      includedEventTypes: [
          'Microsoft.Storage.BlobCreated'
      ]
    }
    labels: [
      'functions-Thumbnail'
    ]
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}
