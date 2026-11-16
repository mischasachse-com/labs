using 'main.bicep'

// APIM name defaults to 'apim-<uniqueString(resourceGroup().id)>' in main.bicep —
// deterministic per RG and globally unique. Override here if you want a fixed name.

// Replace with your own publisher details (used for APIM notification emails).
param publisherEmail = 'you@example.com'
param publisherName = 'Your Name'
