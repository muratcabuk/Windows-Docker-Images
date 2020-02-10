<# abstract #>
class KeyExport {
    KeyExport () {
        if ($this.GetType() -eq [KeyExport]) {
            throw [System.InvalidOperationException]::new("Class must be inherited");
        }
    }

    <# abstract #> [string] TypeName() {
        throw [System.NotImplementedException]::new();
    }
}

class RSAKeyExport : KeyExport {
    hidden [string] $TypeName = "RSAKeyExport";

    [int] $HashSize;

    [byte[]] $Modulus;
    [byte[]] $Exponent;
    [byte[]] $P;
    [byte[]] $Q;
    [byte[]] $DP;
    [byte[]] $DQ;
    [byte[]] $InverseQ;
    [byte[]] $D;
}

class ECDsaKeyExport : KeyExport {
    hidden [string] $TypeName = "ECDsaKeyExport";

    [int] $HashSize;

    [byte[]] $D;
    [byte[]] $X;
    [byte[]] $Y;
}
<# abstract #>
class KeyBase
{
    [ValidateSet(256,384,512)]
    [int]
    hidden $HashSize;

    [System.Security.Cryptography.HashAlgorithmName]
    hidden $HashName;

    KeyBase([int] $hashSize)
    {
        if ($this.GetType() -eq [KeyBase]) {
            throw [System.InvalidOperationException]::new("Class must be inherited");
        }

        $this.HashSize = $hashSize;

        switch ($hashSize)
        {
            256 { $this.HashName = "SHA256";  }
            384 { $this.HashName = "SHA384";  }
            512 { $this.HashName = "SHA512";  }

            default {
                throw [System.ArgumentOutOfRangeException]::new("Cannot set hash size");
            }
        }
    }

    <# abstract #> [KeyExport] ExportKey() {
        throw [System.NotImplementedException]::new();
    }
}
class Certificate {
    static [byte[]] ExportPfx([byte[]] $acmeCertificate, [System.Security.Cryptography.AsymmetricAlgorithm] $algorithm, [securestring] $password) {
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($acmeCertificate);

        if($algorithm -is [System.Security.Cryptography.RSA]) {
            $certifiate = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey($certificate, $algorithm);
        }
        elseif($algorithm -is [System.Security.Cryptography.ECDsa]) {
            $certifiate = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::CopyWithPrivateKey($certificate, $algorithm);
        }
        else {
            throw [System.InvalidOperationException]::new("Cannot use $($algorithm.GetType().Name) to export pfx.");
        }

        if($password) {
            return $certifiate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password);
        } else {
            return $certifiate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx);
        }
    }

    static [byte[]] GenerateCsr([string[]] $dnsNames, [string]$distinguishedName,
        [System.Security.Cryptography.AsymmetricAlgorithm] $algorithm,
        [System.Security.Cryptography.HashAlgorithmName] $hashName)
    {
        if(-not $dnsNames) {
            throw [System.ArgumentException]::new("You need to provide at least one DNSName", "dnsNames");
        }
        if(-not $distinguishedName) {
            thtow [System.ArgumentException]::new("Provide a distinguishedName for the Certificate")
        }

        $sanBuilder = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new();
        foreach ($dnsName in $dnsNames) {
            $sanBuilder.AddDnsName($dnsName);
        }

        $certDN = [X500DistinguishedName]::new($distinguishedName);

        [System.Security.Cryptography.X509Certificates.CertificateRequest]$certRequest = $null;

        if($algorithm -is [System.Security.Cryptography.RSA]) {
            $certRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                    $certDN, $algorithm, $hashName, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1);
        }
        elseif($algorithm -is [System.Security.Cryptography.ECDsa]) {
            $certRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                $certDN, $algorithm, $hashName);

        }
        else {
            throw [System.InvalidOperationException]::new("Cannot use $($algorithm.GetType().Name) to create CSR.");
        }

        $certRequest.CertificateExtensions.Add($sanBuilder.Build());
        return $certRequest.CreateSigningRequest();
    }
}
<# abstract #>
class RSAKeyBase : KeyBase
{
    hidden [System.Security.Cryptography.RSA] $RSA;

    RSAKeyBase([int] $hashSize, [int] $keySize) : base($hashSize)
    {
        if ($this.GetType() -eq [RSAKeyBase]) {
            throw [System.InvalidOperationException]::new("Class must be inherited");
        }

        $this.RSA = [System.Security.Cryptography.RSA]::Create($keySize);
    }

    RSAKeyBase([int] $hashSize, [System.Security.Cryptography.RSAParameters] $keyParameters)
        :base($hashSize)
    {
        if ($this.GetType() -eq [RSAKeyBase]) {
            throw [System.InvalidOperationException]::new("Class must be inherited");
        }

        $this.RSA = [System.Security.Cryptography.RSA]::Create($keyParameters);
    }

    [object] ExportKey() {
        $rsaParams = $this.RSA.ExportParameters($true);

        $keyExport = [RSAKeyExport]::new();

        $keyExport.D = $rsaParams.D;
        $keyExport.DP = $rsaParams.DP;
        $keyExport.DQ = $rsaParams.DQ;
        $keyExport.Exponent = $rsaParams.Exponent;
        $keyExport.InverseQ = $rsaParams.InverseQ;
        $keyExport.Modulus = $rsaParams.Modulus;
        $keyExport.P = $rsaParams.P;
        $keyExport.Q = $rsaParams.Q;

        $keyExport.HashSize = $this.HashSize;

        return $keyExport;
    }
}

class RSAAccountKey : RSAKeyBase, IAccountKey {
    RSAAccountKey([int] $hashSize, [int] $keySize) : base($hashSize, $keySize) { }
    RSAAccountKey([int] $hashSize, [System.Security.Cryptography.RSAParameters] $keyParameters) : base($hashSize, $keyParameters) { }

    [string] JwsAlgorithmName() { return "RS$($this.HashSize)" }

    [System.Collections.Specialized.OrderedDictionary] ExportPublicJwk() {
        $keyParams = $this.RSA.ExportParameters($false);

        <#
            As per RFC 7638 Section 3, these are the *required* elements of the
            JWK and are sorted in lexicographic order to produce a canonical form
        #>
        $publicJwk = [ordered]@{
            "e" = ConvertTo-UrlBase64 -InputBytes $keyParams.Exponent;
            "kty" = "RSA"; # https://tools.ietf.org/html/rfc7518#section-6.3
            "n" = ConvertTo-UrlBase64 -InputBytes $keyParams.Modulus;
        }

        return $publicJwk;
    }

    [byte[]] Sign([byte[]] $inputBytes)
    {
        return $this.RSA.SignData($inputBytes, $this.HashName, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1);
    }

    [byte[]] Sign([string] $inputString)
    {
        return $this.Sign([System.Text.Encoding]::UTF8.GetBytes($inputString));
    }

    static [IAccountKey] Create([RSAKeyExport] $keyExport) {
       $keyParameters = [System.Security.Cryptography.RSAParameters]::new();

       $keyParameters.D = $keyExport.D;
       $keyParameters.DP = $keyExport.DP;
       $keyParameters.DQ = $keyExport.DQ;
       $keyParameters.Exponent = $keyExport.Exponent;
       $keyParameters.InverseQ = $keyExport.InverseQ;
       $keyParameters.Modulus = $keyExport.Modulus;
       $keyParameters.P = $keyExport.P;
       $keyParameters.Q = $keyExport.Q;

       return [RSAAccountKey]::new($keyExport.HashSize, $keyParameters);
    }
}

class RSACertificateKey : RSAAccountKey, ICertificateKey {
    RSACertificateKey([int] $hashSize, [int] $keySize) : base($hashSize, $keySize) { }
    RSACertificateKey([int] $hashSize, [System.Security.Cryptography.RSAParameters] $keyParameters) : base($hashSize, $keyParameters) { }

    [byte[]] ExportPfx([byte[]] $acmeCertificate, [SecureString] $password) {
        return [Certificate]::ExportPfx($acmeCertificate, $this.RSA, $password);
    }

    [byte[]] GenerateCsr([string[]] $dnsNames, [string] $distinguishedName) {
        return [Certificate]::GenerateCsr($dnsNames, $distinguishedName, $this.RSA, $this.HashName);
    }

    static [ICertificateKey] Create([RSAKeyExport] $keyExport) {
        $keyParameters = [System.Security.Cryptography.RSAParameters]::new();

        $keyParameters.D = $keyExport.D;
        $keyParameters.DP = $keyExport.DP;
        $keyParameters.DQ = $keyExport.DQ;
        $keyParameters.Exponent = $keyExport.Exponent;
        $keyParameters.InverseQ = $keyExport.InverseQ;
        $keyParameters.Modulus = $keyExport.Modulus;
        $keyParameters.P = $keyExport.P;
        $keyParameters.Q = $keyExport.Q;

        return [RSACertificateKey]::new($keyExport.HashSize, $keyParameters);
     }
}
<# abstract #>
class ECDsaKeyBase : KeyBase
{
    hidden [System.Security.Cryptography.ECDsa] $ECDsa;
    hidden [string] $CurveName

    ECDsaKeyBase([int] $hashSize) : base($hashSize)
    {
        if ($this.GetType() -eq [ECDsaKeyBase]) {
            throw [System.InvalidOperationException]::new("Class must be inherited");
        }

        $this.CurveName = "P-$hashSize";
        $curve = [ECDsaKeyBase]::GetCurve($hashSize);

        $this.ECDsa = [System.Security.Cryptography.ECDsa]::Create($curve);
    }

    ECDsaKeyBase([int] $hashSize,[System.Security.Cryptography.ECParameters] $keyParameters)
        :base($hashSize)
    {
        if ($this.GetType() -eq [ECDsaKeyBase]) {
            throw [System.InvalidOperationException]::new("Class must be inherited");
        }

        $this.CurveName = "P-$hashSize";
        $this.ECDsa = [System.Security.Cryptography.ECDsa]::Create($keyParameters);
    }

    static [System.Security.Cryptography.ECCurve] GetCurve($hashSize) {
        switch ($hashSize) {
            256 { return [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256; }
            384 { return [System.Security.Cryptography.ECCurve+NamedCurves]::nistP384; }
            512 { return [System.Security.Cryptography.ECCurve+NamedCurves]::nistP521; }
            Default { throw [System.ArgumentOutOfRangeException]::new("Cannot use hash size to create curve."); }
        }

        return $null;
    }

    [object] ExportKey() {
        $ecParams = $this.ECDsa.ExportParameters($true);
        $keyExport = [ECDsaKeyExport]::new();

        $keyExport.D = $ecParams.D;
        $keyExport.X = $ecParams.Q.X;
        $keyExport.Y = $ecParams.Q.Y;

        $keyExport.HashSize = $this.HashSize;

        return $keyExport;
    }
}

class ECDsaAccountKey : ECDsaKeyBase, IAccountKey {
    ECDsaAccountKey([int] $hashSize) : base($hashSize) { }
    ECDsaAccountKey([int] $hashSize, [System.Security.Cryptography.ECParameters] $keyParameters) : base($hashSize, $keyParameters) { }

    [string] JwsAlgorithmName() { return "ES$($this.HashSize)" }

    [System.Collections.Specialized.OrderedDictionary] ExportPublicJwk() {
        $keyParams = $this.ECDsa.ExportParameters($false);

        <#
            As per RFC 7638 Section 3, these are the *required* elements of the
            JWK and are sorted in lexicographic order to produce a canonical form
        #>
        $publicJwk = [ordered]@{
            "crv" = $this.CurveName;
            "kty" = "EC"; # https://tools.ietf.org/html/rfc7518#section-6.2
            "x" = ConvertTo-UrlBase64 -InputBytes $keyParams.Q.X;
            "y" = ConvertTo-UrlBase64 -InputBytes $keyParams.Q.Y;
        }

        return $publicJwk;
    }

    [byte[]] Sign([byte[]] $inputBytes)
    {
        return $this.ECDsa.SignData($inputBytes, $this.HashName);
    }

    [byte[]] Sign([string] $inputString)
    {
        return $this.Sign([System.Text.Encoding]::UTF8.GetBytes($inputString));
    }

    static [IAccountKey] Create([ECDsaKeyExport] $keyExport) {
        $keyParameters = [System.Security.Cryptography.ECParameters]::new();

        $keyParameters.Curve = [ECDsaKeyBase]::GetCurve($keyExport.HashSize);
        $keyParameters.D = $keyExport.D;

        $q = [System.Security.Cryptography.ECPoint]::new();
        $q.X = $keyExport.X;
        $q.Y = $keyExport.Y;
        $keyParameters.Q = $q;

        return [ECDsaAccountKey]::new($keyExport.HashSize, $keyParameters);
     }
}

class ECDsaCertificateKey : ECDsaAccountKey, ICertificateKey {
    ECDsaCertificateKey([int] $hashSize) : base($hashSize) { }
    ECDsaCertificateKey([int] $hashSize, [System.Security.Cryptography.ECParameters] $keyParameters) : base($hashSize, $keyParameters) { }

    [byte[]] ExportPfx([byte[]] $acmeCertificate, [SecureString] $password) {
        return [Certificate]::ExportPfx($acmeCertificate, $this.ECDsa, $password);
    }

    [byte[]] GenerateCsr([string[]] $dnsNames, [string] $distinguishedName) {
        return [Certificate]::GenerateCsr($dnsNames, $distinguishedName, $this.ECDsa, $this.HashName);
    }

    static [ICertificateKey] Create([ECDsaKeyExport] $keyExport) {
        $keyParameters = [System.Security.Cryptography.ECParameters]::new();

        $keyParameters.Curve = [ECDsaKeyBase]::GetCurve($keyExport.HashSize);
        $keyParameters.D = $keyExport.D;

        $q = [System.Security.Cryptography.ECPoint]::new();
        $q.X = $keyExport.X;
        $q.Y = $keyExport.Y;
        $keyParameters.Q = $q;

        return [ECDsaCertificateKey]::new($keyExport.HashSize, $keyParameters);
     }
}
class KeyAuthorization {
    static hidden [byte[]] ComputeThumbprint([IAccountKey] $accountKey, [System.Security.Cryptography.HashAlgorithm] $hashAlgorithm)
    {
        $jwkJson = $accountKey.ExportPublicJwk() | ConvertTo-Json -Compress;
        $jwkBytes = [System.Text.Encoding]::UTF8.GetBytes($jwkJson);
        $jwkHash = $hashAlgorithm.ComputeHash($jwkBytes);

        return $jwkHash;
    }


    static [string] Compute([IAccountKey] $accountKey, [string] $token)
    {
        $sha256 = [System.Security.Cryptography.SHA256]::Create();

        try {
            $thumbprintBytes = [KeyAuthorization]::ComputeThumbprint($accountKey, $sha256);
            $thumbprint = ConvertTo-UrlBase64 -InputBytes $thumbprintBytes;
            return "$token.$thumbprint";
        } finally {
            $sha256.Dispose();
        }
    }

    static [string] ComputeDigest([IAccountKey] $accountKey, [string] $token)
    {
        $sha256 = [System.Security.Cryptography.SHA256]::Create();

        try {
            $thumbprintBytes = [KeyAuthorization]::ComputeThumbprint($accountKey, $sha256);
            $thumbprint = ConvertTo-UrlBase64 -InputBytes $thumbprintBytes;
            $keyAuthZBytes = [System.Text.Encoding]::UTF8.GetBytes("$token.$thumbprint");

            $digest = $sha256.ComputeHash($keyAuthZBytes);
            return ConvertTo-UrlBase64 -InputBytes $digest;
        } finally {
            $sha256.Dispose();
        }
    }
}
class Creator {
    [Type] $TargetType;
    [Type] $KeyType;
    [Func[[KeyExport], [KeyBase]]] $Create;

    Creator([Type] $targetType, [Type] $keyType, [Func[[KeyExport], [KeyBase]]] $creatorFunction)
    {
        $this.TargetType = $targetType;
        $this.KeyType = $keyType;
        $this.Create = $creatorFunction;
    }
}

class KeyFactory
{
    static [System.Collections.ArrayList] $Factories =
    @(
        [Creator]::new("IAccountKey", "RSAKeyExport", { param($k) return [RSAAccountKey]::Create($k) }),
        [Creator]::new("ICertificateKey", "RSAKeyExport", { param($k) return [RSACertificateKey]::Create($k) }),

        [Creator]::new("IAccountKey", "ECDsaKeyExport", { param($k) return [ECDsaAccountKey]::Create($k) }),
        [Creator]::new("ICertificateKey", "ECDsaKeyExport", { param($k) return [ECDsaCertificateKey]::Create($k) })
    );

    hidden static [KeyBase] Create([Type] $targetType, [KeyExport] $keyParameters)
    {
        $keyType = $keyParameters.GetType();
        $factory = [KeyFactory]::Factories | Where-Object { $_.TargetType -eq $targetType -and $_.KeyType -eq $keyType } | Select-Object -First 1

        if ($null -eq $factory) {
            throw [InvalidOperationException]::new("Unknown KeyParameters-Type.");
        }

        return $factory.Create.Invoke($keyParameters);
    }

    static [IAccountKey] CreateAccountKey([KeyExport] $keyParameters) {
        return [KeyFactory]::Create("IAccountKey", $keyParameters);
    }
    static [ICertificateKey] CreateCertificateKey([KeyExport] $keyParameters) {
        return [KeyFactory]::Create("ICertificateKey", $keyParameters);
    }
}
class AcmeHttpResponse {
    AcmeHttpResponse() {}

    AcmeHttpResponse([System.Net.Http.HttpResponseMessage] $responseMessage) {
        $this.RequestUri = $responseMessage.RequestMessage.RequestUri;
        
        $this.StatusCode = $responseMessage.StatusCode;
        if($this.StatusCode -ge 400) {
            Write-Debug "StatusCode was > 400, Setting IsError true."
            $this.IsError = $true;
        }

        $this.Headers = @{};
        foreach($h in $responseMessage.Headers) {
            Write-Debug "Add Header $($h.Key) with $($h.Value)"
            $this.Headers.Add($h.Key, $h.Value);

            if($h.Key -eq "Replay-Nonce") {
                Write-Debug "Found Replay-Nonce-Header $($h.Value[0])"
                $this.NextNonce = $h.Value[0];
            }
        }

        $contentType = if ($null -ne $responseMessage.Content) { $responseMessage.Content.Headers.ContentType } else { "N/A" };
        Write-Debug "Content-type is $contentType"
        if($contentType -imatch "application/(.*\+)?json") {
            $stringContent = $responseMessage.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            $this.Content = $stringContent | ConvertFrom-Json;

            if($contentType -eq "application/problem+json") {
                $this.IsError = $true;
                $this.ErrorMessage = "Server returned problem (Status: $($this.StatusCode))."
            }
        } 
        elseif ($contentType -ieq "application/pem-certificate-chain") {
            $this.Content = [byte[]]$responseMessage.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
        }
        else {
            try {
                $this.Content = $responseMessage.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            } catch {
                $this.Content = "";
            }

            if ($this.StatusCode -ge 400) {
                $this.ErrorMessage = "Unexpected server response (Status: $($this.StatusCode), ContentType: $contentType)."
            }
        }
    }

    [string] $RequestUri;
    [int] $StatusCode;
    
    [string] $NextNonce;

    [hashtable] $Headers;
    $Content;

    [bool] $IsError;
    [string] $ErrorMessage;
}
class AcmeDirectory {
    AcmeDirectory([PSCustomObject] $obj) {
        $this.ResourceUrl = $obj.ResourceUrl

        $this.NewAccount = $obj.NewAccount;
        $this.NewAuthz = $obj.NewAuthz;
        $this.NewNonce = $obj.NewNonce;
        $this.NewOrder = $obj.NewOrder;
        $this.KeyChange = $obj.KeyChange;
        $this.RevokeCert = $obj.RevokeCert;

        $this.Meta = [AcmeDirectoryMeta]::new($obj.Meta);
    }

    [string] $ResourceUrl;

    [string] $NewAccount;
    [string] $NewAuthz;
    [string] $NewNonce;
    [string] $NewOrder;
    [string] $KeyChange;
    [string] $RevokeCert;

    [AcmeDirectoryMeta] $Meta;
}

class AcmeDirectoryMeta {
    AcmeDirectoryMeta([PSCustomObject] $obj) {
        $this.CaaIdentites = $obj.CaaIdentities;
        $this.TermsOfService = $obj.TermsOfService;
        $this.Website = $obj.Website;
    }

    [string[]] $CaaIdentites;
    [string] $TermsOfService;
    [string] $Website;
}
class AcmeAccount {
    AcmeAccount() {}

    AcmeAccount([AcmeHttpResponse] $httpResponse, [string] $KeyId)
    {
        $this.KeyId = $KeyId;

        $this.Status = $httpResponse.Content.Status;
        $this.Id = $httpResponse.Content.Id;
        $this.Contact = $httpResponse.Content.Contact;
        $this.InitialIp = $httpResponse.Content.InitialIp;
        $this.CreatedAt = $httpResponse.Content.CreatedAt;

        $this.OrderListUrl = $httpResponse.Content.Orders;
        $this.ResourceUrl = $KeyId;
    }

    [string] $ResourceUrl;

    [string] $KeyId;

    [string] $Status;

    [string] $Id;
    [string[]] $Contact;
    [string] $InitialIp;
    [string] $CreatedAt;

    [string] $OrderListUrl;
}
class AcmeIdentifier {
    AcmeIdentifier([string] $type, [string] $value) {
        $this.Type = $type;
        $this.Value = $value;
    }

    AcmeIdentifier([PsCustomObject] $obj) {
        $this.type = $obj.type;
        $this.value = $obj.Value;
    }

    [string] $type;
    [string] $value;

    [string] ToString() {
        return "$($this.Type.ToLower()):$($this.Value.ToLower())";
    }
}
class AcmeChallenge {
    AcmeChallenge([PSCustomObject] $obj, [AcmeIdentifier] $identifier) {
        $this.Type = $obj.type;
        $this.Url = $obj.url;
        $this.Token = $obj.token;

        $this.Identifier = $identifier;
    }

    [string] $Type;
    [string] $Url;
    [string] $Token;

    [AcmeIdentifier] $Identifier;

    [PSCustomObject] $Data;
}
class AcmeCsrOptions {
    AcmeCsrOptions() { }

    AcmeCsrOptions([PsCustomObject] $obj) {
        $this.DistinguishedName = $obj.DistinguishedName
    }

    [string]$DistinguishedName;
}
class AcmeOrder {
    AcmeOrder([PsCustomObject] $obj) {
        $this.Status = $obj.Status;
        $this.Expires  = $obj.Expires;
        $this.NotBefore = $obj.NotBefore;
        $this.NotAfter = $obj.NotAfter;

        $this.Identifiers = $obj.Identifiers | ForEach-Object { [AcmeIdentifier]::new($_) };

        $this.AuthorizationUrls = $obj.AuthorizationUrls;
        $this.FinalizeUrl = $obj.FinalizeUrl;
        $this.CertificateUrl = $obj.CertificateUrl;

        $this.ResourceUrl = $obj.ResourceUrl;

        if($obj.CSROptions) {
            $this.CSROptions = [AcmeCsrOptions]::new($obj.CSROptions)
        } else {
            $this.CSROptions = [AcmeCsrOptions]::new()
        }
    }

    AcmeOrder([AcmeHttpResponse] $httpResponse)
    {
        $this.UpdateOrder($httpResponse)
        $this.CSROptions = [AcmeCsrOptions]::new();
    }

    AcmeOrder([AcmeHttpResponse] $httpResponse, [AcmeCsrOptions] $csrOptions)
    {
        $this.UpdateOrder($httpResponse)

        if($csrOptions) {
            $this.CSROptions = $csrOptions;
        } else {
            $this.CSROptions = [AcmeCSROptions]::new()
        }
    }

    [void] UpdateOrder([AcmeHttpResponse] $httpResponse) {
        $this.Status = $httpResponse.Content.Status;
        $this.Expires  = $httpResponse.Content.Expires;

        $this.NotBefore = $httpResponse.Content.NotBefore;
        $this.NotAfter = $httpResponse.Content.NotAfter;

        $this.Identifiers = $httpResponse.Content.Identifiers | ForEach-Object { [AcmeIdentifier]::new($_) };

        $this.AuthorizationUrls = $httpResponse.Content.Authorizations;
        $this.FinalizeUrl = $httpResponse.Content.Finalize;

        $this.CertificateUrl = $httpResponse.Content.Certificate;

        if($httpResponse.Headers.Location) {
            $this.ResourceUrl = $httpResponse.Headers.Location[0];
        } else {
            $this.ResourceUrl = $httpResponse.RequestUri;
        }
    }

    [string] $ResourceUrl;

    [string] $Status;
    [string] $Expires;

    [Nullable[System.DateTimeOffset]] $NotBefore;
    [Nullable[System.DateTimeOffset]] $NotAfter;

    [AcmeIdentifier[]] $Identifiers;

    [string[]] $AuthorizationUrls;
    [string] $FinalizeUrl;

    [string] $CertificateUrl;

    [AcmeCsrOptions] $CSROptions;
}
class AcmeAuthorization {
    AcmeAuthorization([AcmeHttpResponse] $httpResponse)
    {
        $this.status = $httpResponse.Content.status;
        $this.expires = $httpResponse.Content.expires;

        $this.identifier = [AcmeIdentifier]::new($httpResponse.Content.identifier);
        $this.challenges = @($httpResponse.Content.challenges | ForEach-Object { [AcmeChallenge]::new($_, $this.identifier) });

        $this.wildcard = $httpResponse.Content.wildcard;
        $this.ResourceUrl = $httpResponse.RequestUri;
    }

    [string] $ResourceUrl;

    [string] $Status;
    [System.DateTimeOffset] $Expires;

    [AcmeIdentifier] $Identifier;
    [AcmeChallenge[]] $Challenges;

    [bool] $Wildcard;
}
class AcmeState {
    [ValidateNotNull()] hidden [AcmeDirectory] $ServiceDirectory;
    [ValidateNotNull()] hidden [string] $Nonce;
    [ValidateNotNull()] hidden [IAccountKey] $AccountKey;
    [ValidateNotNull()] hidden [AcmeAccount] $Account;

    hidden [string] $SavePath;
    hidden [bool] $AutoSave;
    hidden [bool] $IsInitializing;

    hidden [AcmeStatePaths] $Filenames;

    AcmeState() {
        $this.Filenames = [AcmeStatePaths]::new("");
    }

    AcmeState([string] $savePath, [bool]$autoSave) {
        $this.Filenames = [AcmeStatePaths]::new($savePath);

        if(-not (Test-Path $savePath)) {
            New-Item $savePath -ItemType Directory -Force;
        }

        $this.AutoSave = $autoSave;
        $this.SavePath = Resolve-Path $savePath;
    }


    [AcmeDirectory] GetServiceDirectory() { return $this.ServiceDirectory; }
    [string] GetNonce() { return $this.Nonce; }
    [IAccountKey] GetAccountKey() { return $this.AccountKey; }
    [AcmeAccount] GetAccount() { return $this.Account; }


    [void] Set([AcmeDirectory] $serviceDirectory) {
        $this.ServiceDirectory = $serviceDirectory;
        if($this.AutoSave) {
            $directoryPath = $this.Filenames.ServiceDirectory;

            Write-Debug "Storing the service directory to $directoryPath";
            $this.ServiceDirectory | Export-AcmeObject $directoryPath -Force;
        }
    }
    [void] SetNonce([string] $nonce) {
        $this.Nonce = $nonce;
        if($this.AutoSave) {
            $noncePath = $this.Filenames.Nonce;
            Set-Content $noncePath -Value $nonce -NoNewLine;
        }
    }
    [void] Set([IAccountKey] $accountKey) {
        $this.AccountKey = $accountKey;

        if($this.AutoSave) {
            $accountKeyPath = $this.Filenames.AccountKey;
            $this.AccountKey | Export-AccountKey $accountKeyPath -Force;
        } elseif(-not $this.IsInitializing) {
            Write-Warning "The account key will not be exported."
            Write-Information "Make sure you save the account key or you might loose access to your ACME account.";
        }
    }
    [void] Set([AcmeAccount] $account) {
        $this.Account = $account;
        if($this.AutoSave) {
            $accountPath = $this.Filenames.Account;
            $this.Account | Export-AcmeObject $accountPath;
        }
    }

    hidden [void] LoadFromPath()
    {
        $this.IsInitializing = $true;
        $this.AutoSave = $false;

        $directoryPath = $this.Filenames.ServiceDirectory;
        $noncePath = $this.Filenames.Nonce;
        $accountKeyPath = $this.Filenames.AccountKey;
        $accountPath = $this.Filenames.Account;

        if(Test-Path $directoryPath) {
            Get-ServiceDirectory $this -Path $directoryPath
        } else {
            Write-Verbose "Could not find saved service directory at $directoryPath";
        }

        if(Test-Path $noncePath) {
            $importedNonce = Get-Content $noncePath -Raw
            if($importedNonce) {
                $this.SetNonce($importedNonce);
            } else {
                New-Nonce $this;
            }
        } else {
            Write-Verbose "Could not find saved nonce at $noncePath";
        }

        if(Test-Path $accountKeyPath) {
            Import-AccountKey $this -Path $accountKeyPath
        } else {
            Write-Verbose "Could not find saved account key at $accountKeyPath";
        }

        if(Test-Path $accountPath) {
            $importedAccount = Import-AcmeObject -Path $accountPath -TypeName "AcmeAccount"
            $this.Set($importedAccount);
        } else {
            Write-Verbose "Could not find saved account at $accountPath";
        }

        $this.AutoSave = $true;
        $this.IsInitializing = $false
    }

    hidden [string] GetOrderHash([AcmeOrder] $order) {
        $orderIdentifiers = $order.Identifiers | Foreach-Object { $_.ToString() } | Sort-Object;
        $identifier = [string]::Join('|', $orderIdentifiers);

        $sha256 = [System.Security.Cryptography.SHA256]::Create();
        try {
            $identifierBytes = [System.Text.Encoding]::UTF8.GetBytes($identifier);
            $identifierHash = $sha256.ComputeHash($identifierBytes);
            $result = ConvertTo-UrlBase64 -InputBytes $identifierHash;

            return $result;
        } finally {
            $sha256.Dispose();
        }
    }
    hidden [string] GetOrderFileName([string] $orderHash) {
        $fileName = $this.Filenames.Order.Replace("[hash]", $orderHash);
        return $fileName;
    }

    hidden [AcmeOrder] LoadOrder([string] $orderHash) {
        $orderFile = $this.GetOrderFileName($orderHash);
        if(Test-Path $orderFile) {
            $order = Import-AcmeObject -Path $orderFile -TypeName "AcmeOrder";
            return $order;
        }

        return $null;
    }

    [void] AddOrder([AcmeOrder] $order) {
        $this.SetOrder($order);
    }

    [void] SetOrder([AcmeOrder] $order) {
        if($this.AutoSave) {
            $orderHash = $this.GetOrderHash($order);
            $orderFileName = $this.GetOrderFileName($orderHash);

            if(-not (Test-Path $order)) {
                $orderListFile = $this.Filenames.OrderList;

                foreach ($id in $order.Identifiers) {
                    if(-not (Test-Path $orderListFile)) {
                        New-Item $orderListFile -Force;
                    }

                    "$($id.ToString())=$orderHash" | Add-Content $orderListFile;
                }
            }

            $order | Export-AcmeObject $orderFileName -Force;
        } else {
            Write-Warning "auto saving the state has been disabled, so set order is a no-op."
        }
    }

    [void] RemoveOrder([AcmeOrder] $order) {
        if($this.AutoSave) {
            $orderHash = $this.GetOrderHash($order);
            $orderFileName = $this.GetOrderFileName($orderHash);

            if(Test-Path $orderFileName) {
                Remove-Item $orderFileName;
            }

            $orderListFile = $this.Filenames.OrderList;
            Set-Content -Path $orderListFile -Value (Get-Content -Path $orderListFile | Select-String -Pattern "=$orderHash" -NotMatch -SimpleMatch)
        } else {
            Write-Warning "auto saving the state has been disabled, so set order is a no-op."
        }
    }

    [AcmeOrder] FindOrder([string[]] $dnsNames) {
        $orderListFile = $this.Filenames.OrderList;

        $first = $true;
        $lastMatch = $null;
        foreach($dnsName in $dnsNames) {
            $match = Select-String -Path $orderListFile -Pattern "$dnsName=" -SimpleMatch | Select-Object -Last 1
            if($first) { $lastMatch = $match; }
            if($match -ne $lastMatch) { return $null; }

            $lastMatch = $match;
        }

        $orderHash = ($lastMatch -split "=", 2)[1];
        return $this.LoadOrder($orderHash);
    }

    [bool] Validate() {
        return $this.Validate("Account");
    }

    [bool] Validate([string] $field) {
        $isValid = $true;

        if($field -in @("ServiceDirectory", "Nonce", "AccountKey", "Account")) {
            if($null -eq $this.ServiceDirectory) {
                $isValid = $false;
                Write-Warning "State does not contain a service directory. Run Get-ACMEServiceDirectory to get one."
            }
        }

        if($field -in @("Nonce", "AccountKey", "Account")) {
            if($null -eq $this.Nonce) {
                $isValid = $false;
                Write-Warning "State does not contain a nonce. Run New-ACMENonce to get one."
            }
        }

        if($field -in @("AccountKey", "Account")) {
            if($null -eq $this.AccountKey) {
                $isValid = $false;
                Write-Warning "State does not contain an account key. Run New-ACMEAccountKey to create one."
            }
        }

        if($field -in @("Account")) {
            if($null -eq $this.Account) {
                $isValid = $false;
                Write-Warning "State does not contain an account. Register one by running New-ACMEAccount."
            }
        }

        return $isValid;
    }

    static [AcmeState] FromPath([string] $Path) {
        $state = [AcmeState]::new($Path, $false);
        $state.LoadFromPath();

        return $state;
    }
}

class AcmeStatePaths {
    [string] $ServiceDirectory;
    [string] $Nonce;
    [string] $AccountKey;
    [string] $Account;

    [string] $OrderList;
    [string] $Order;

    AcmeStatePaths([string] $basePath) {
        $this.ServiceDirectory = "$basePath/ServiceDirectory.xml";
        $this.Nonce = "$basePath/NextNonce.txt";
        $this.AccountKey = "$basePath/AccountKey.xml";
        $this.Account = "$basePath/Account.xml";

        $this.OrderList = "$basePath/Orders/OrderList.txt"
        $this.Order = "$basePath/Orders/Order-[hash].xml";
    }
}
function ConvertTo-OriginalType {
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        $inputObject,

        [Parameter(Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [string]
        $TypeName
    )

    process {
        $result = $inputObject -as ([type]$TypeName);
        if(-not $result) {
            throw "Could not convert inputObject to $TypeName";
        }

        Write-Verbose "Converted input object to type $TypeName";
        return $result;
    }
}

function ConvertTo-UrlBase64 {
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName="FromString")]
        [ValidateNotNull()]
        [string] $InputText,

        [Parameter(Mandatory = $true, ParameterSetName="FromByteArray")]
        [ValidateNotNull()]
        [byte[]] $InputBytes
    )

    if($PSCmdlet.ParameterSetName -eq "FromString") {
        $InputBytes = [System.Text.Encoding]::UTF8.GetBytes($InputText);
    }

    $encoded = [System.Convert]::ToBase64String($InputBytes);

    $encoded = $encoded.TrimEnd('=');
    $encoded = $encoded.Replace('+', '-');
    $encoded = $encoded.Replace('/', '_');

    return $encoded;
}
function Export-AcmeObject {
    param(
        [Parameter(Mandatory=$true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory=$true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        $InputObject,

        [Parameter()]
        [switch]
        $Force
    )

    process {
        $ErrorActionPreference = 'Stop'

        if((Test-Path $Path) -and -not $Force) {
            throw "$Path already exists."
        }

        Write-Debug "Exporting $($InputObject.GetType()) to $Path"
        if($Path -like "*.json") {
            Write-Verbose "Exporting object to JSON file $Path"
            $InputObject | ConvertTo-Json | Out-File -FilePath $Path -Encoding utf8 -Force:$Force;
        } else {
            Write-Verbose "Exporting object to CLIXML file $Path"
            Export-Clixml $Path -InputObject $InputObject -Force:$Force;
        }
    }
}
function Import-AcmeObject {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path $_})]
        [string]
        $Path,

        [Parameter()]
        [string]
        $TypeName
    )

    process {
        $ErrorActionPreference = 'Stop'

        if($Path -like "*.json") {
            Write-Verbose "Importing object from JSON file $Path"
            $imported = Get-Content $Path -Raw | ConvertFrom-Json;
        } else {
            Write-Verbose "Importing object from CLIXML file $Path"
            $imported = Import-Clixml $Path;
        }

        if($TypeName) {
            $result = $imported | ConvertTo-OriginalType -TypeName $TypeName
        } else {
            $result = $imported | ConvertTo-OriginalType
        }

        return $result;
    }
}
function Invoke-ACMEWebRequest {
    <#
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [Alias("Url")]
        [uri] $Uri,

        [Parameter(Position = 1)]
        [ValidateNotNull()]
        [string]
        $JsonBody,

        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST", "HEAD")]
        [string]
        $Method
    )

    $httpRequest = [System.Net.Http.HttpRequestMessage]::new($Method, $Uri);
    Write-Verbose "Sending HttpRequest ($Method) to $Uri";

    if($Method -in @("POST", "PUT")) {
        $httpRequest.Content = [System.Net.Http.StringContent]::new($JsonBody, [System.Text.Encoding]::UTF8);
        $httpRequest.Content.Headers.ContentType = "application/jose+json";

        Write-Debug "The content of the request is $JsonBody";
    }

    #TODO: This should possibly swapped out to be something singleton-ish.
    $httpClient = [System.Net.Http.HttpClient]::new();

    $httpResponse = $httpClient.SendAsync($httpRequest).GetAwaiter().GetResult();

    $result = [AcmeHttpResponse]::new($httpResponse);
    return $result;
}
function Invoke-SignedWebRequest {
    [CmdletBinding()]
    [OutputType("AcmeHttpResponse")]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Url,

        [Parameter(Mandatory = $true, Position = 1)]
        [AcmeState] $State,

        [Parameter(Position = 2)]
        [ValidateNotNull()]
        [object] $Payload = "",

        [Parameter()]
        [switch] $SupressKeyId
    )

    process {
        $accountKey = $State.GetAccountKey();
        $account = $State.GetAccount();
        $keyId = $(if($account -and -not $SupressKeyId) { $account.KeyId });
        $nonce = $State.GetNonce();

        $requestBody = New-SignedMessage -Url $Url -SigningKey $accountKey -KeyId $keyId -Nonce $nonce -Payload $Payload
        $response = Invoke-AcmeWebRequest $Url $requestBody -Method POST -ErrorAction 'Continue'

        if($null -ne $response -and $response.NextNonce) {
            $State.SetNonce($response.NextNonce);
        }

        if($response.IsError) {
            throw "$($response.ErrorMessage)`n$($response.Content)";
        }

        return $response;
    }
}
function New-SignedMessage {
    [CmdletBinding(SupportsShouldProcess=$false)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions", "", Scope="Function", Target="*")]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Url,

        [Parameter(Mandatory = $true, Position = 1)]
        [ISigningKey] $SigningKey,

        [Parameter(Position = 2)]
        [string] $KeyId,

        [Parameter(Position = 3)]
        [string] $Nonce,

        [Parameter(Mandatory = $true, Position = 4)]
        [ValidateNotNull()]
        [object] $Payload
    )

    $headers = @{};
    $headers.Add("alg", $SigningKey.JwsAlgorithmName());
    $headers.Add("url", $Url);

    if($Nonce) {
        Write-Debug "Nonce $Nonce will be used";
        $headers.Add("nonce", $Nonce);
    }

    if($KeyId) {
        Write-Debug "KeyId $KeyId will be used";
        $headers.Add("kid", $KeyId);
    }

    if(-not ($KeyId)) {
        Write-Debug "No KeyId present, addind JWK.";
        $headers.Add("jwk", $SigningKey.ExportPublicJwk());
    }

    if($null -eq $Payload -or $Payload -is [string]) {
        Write-Debug "Payload was string, using without Conversion."
        $messagePayload = $Payload;
    } else {
        Write-Debug "Payload was object, converting to Json";
        $messagePayload = $Payload | ConvertTo-Json -Compress;
    }

    $jsonHeaders = $headers | ConvertTo-Json -Compress

    Write-Debug "Payload is now: $messagePayload";
    Write-Debug "Headers are: $jsonHeaders"

    $signedPayload = @{};

    $signedPayload.add("header", $null);
    $signedPayload.add("protected", (ConvertTo-UrlBase64 -InputText $jsonHeaders));
    if($null -eq $messagePayload -or $messagePayload.Length -eq 0) {
        $signedPayload.add("payload", "");
    } else {
        $signedPayload.add("payload", (ConvertTo-UrlBase64 -InputText $messagePayload));
    }
    $signedPayload.add("signature", (ConvertTo-UrlBase64 -InputBytes $SigningKey.Sign("$($signedPayload.Protected).$($signedPayload.Payload)")));

    $result = $signedPayload | ConvertTo-Json;
    Write-Debug "Created signed message`n: $result";

    return $result;
}
function Get-Account {
    <#
        .SYNOPSIS
            Loads account data from the ACME service.

        .DESCRIPTION
            If you do not provide additional parameters, this will search the account with the account key
            present in the state object. If an KeyId or Url is provided, they'll be used to load the account
            from that.

        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER PassThru
            Forces the retreieved account to be returned to the pipeline.

        .PARAMETER AccountUrl
            The rescource url of the account to load.

        .PARAMETER KeyId
            The KeyId of the account to load.


        .EXAMPLE
            PS> Get-Account -State $myState -PassThru

        .EXAMPLE
            PS> Get-Account -State $myState -KeyId 12345
    #>
    [CmdletBinding(DefaultParameterSetName = "FindAccount")]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate("AccountKey")})]
        [AcmeState]
        $State,

        [Parameter()]
        [switch]
        $PassThru,

        [Parameter(Mandatory = $true, Position = 1, ParameterSetName="GetAccount")]
        [ValidateNotNull()]
        [uri] $AccountUrl,

        [Parameter(Mandatory = $true, Position = 2, ParameterSetName="GetAccount")]
        [ValidateNotNullOrEmpty()]
        [string] $KeyId
    )

    if($PSCmdlet.ParameterSetName -eq "FindAccount") {
        $requestUrl = $State.GetServiceDirectory().NewAccount;
        $payload = @{"onlyReturnExisting" = $true};
        $response = Invoke-SignedWebRequest $requestUrl $State $payload

        if($response.StatusCode -eq 200) {
            $KeyId = $response.Headers["Location"][0];

            $AccountUrl = $KeyId;
        } else {
            Write-Error "JWK seems not to be registered for an account."
            return $null;
        }
    }

    $response = Invoke-SignedWebRequest $AccountUrl $State @{}
    $result = [AcmeAccount]::new($response, $KeyId);

    if($AutomaticAccountHandling) {
        Enable-AccountHandling -Account $result;
    }

    return $result;
}
function New-Account {
    <#
        .SYNOPSIS
            Registers your account key with a new ACME-Account.

        .DESCRIPTION
            Registers the given account key with an ACME service to retreive an account that enables you to
            communicate with the ACME service.


        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER PassThru
            Forces the account to be returned to the pipeline.

        .PARAMETER AcceptTOS
            If you set this, you accepted the Terms-of-service.

        .PARAMETER ExistingAccountIsError
            If set, the script will throw an error, if the key has already been registered.
            If not set, the script will try to fetch the account associated with the account key.

        .PARAMETER EmailAddresses
            Contact adresses for certificate expiration mails and similar.


        .EXAMPLE
            PS> New-Account -AcceptTOS -EmailAddresses "mail@example.com" -AutomaticAccountHandling

        .EXAMPLE
            PS> New-Account $myServiceDirectory $myAccountKey $myNonce -AcceptTos -EmailAddresses @(...) -ExistingAccountIsError
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate("AccountKey")})]
        [AcmeState]
        $State,

        [Parameter()]
        [switch]
        $PassThru,

        [Switch]
        $AcceptTOS,

        [Switch]
        $ExistingAccountIsError,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $EmailAddresses
    )

    $Contacts = @($EmailAddresses | ForEach-Object { if($_.StartsWith("mailto:")) { $_ } else { "mailto:$_" } });

    $payload = @{
        "TermsOfServiceAgreed"=$AcceptTOS.IsPresent;
        "Contact"=$Contacts;
    }

    $url = $State.GetServiceDirectory().NewAccount;

    if($PSCmdlet.ShouldProcess("New-Account", "Sending account registration to ACME Server $Url")) {
        $response = Invoke-SignedWebRequest $url $State $payload -SupressKeyId -ErrorAction 'Stop'

        if($response.StatusCode -eq 200) {
            if(-not $ExistingAccountIsError) {
                Write-Warning "JWK had already been registered for an account - trying to fetch account."

                $keyId = $response.Headers["Location"][0];

                return Get-Account -AccountUrl $keyId -KeyId $keyId -State $State -PassThru:$PassThru
            } else {
                Write-Error "JWK had already been registiered for an account."
                return;
            }
        }

        $account = [AcmeAccount]::new($response, $response.Headers["Location"][0]);
        $State.Set($account);

        if($PassThru) {
            return $account;
        }
    }
}
function Set-Account {
    <#
        .SYNOPSIS
            Updates an ACME account

        .DESCRIPTION
            Updates the ACME account, by sending the update information to the ACME service.

        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER PassThru
            Forces the updated account to be returned to the pipeline.

        .PARAMETER NewAccountKey
            New account key to be associated with the account.


        .EXAMPLE
            PS> Set-Account -State $myState -NewAccountKey $myNewAccountKey
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State,

        [Parameter()]
        [switch]
        $PassThru,

        [Parameter(Mandatory = $true, ParameterSetName="NewAccountKey")]
        [IAccountKey] $NewAccountKey
    )

    $innerPayload = @{
        "account" = $State.GetAccount().KeyId;
        "oldKey" = $State.GetAccountKey().ExportPuplicKey()
    };

    $payload = New-SignedMessage -Url $Url -SigningKey $NewAccountKey -Payload $innerPayload;

    if($PSCmdlet.ShouldProcess("Account", "Set new AccountKey and store it into state")) {
        Invoke-SignedWebRequest $Url -$State $payload -ErrorAction 'Stop';

        $State.Set($NewAccountKey);
        $account = Get-Account -Url $TargetAccount.ResourceUrl -State $State -KeyId $Account.KeyId

        $State.Set($account);

        if($PassThru) {
            return $account;
        }
    }
}
function Export-AccountKey {
    <#
        .SYNOPSIS
            Stores an account key to the given path.

        .DESCRIPTION
            Stores an account key to the given path. If the path already exists an error will be thrown and the key will not be saved.


        .PARAMETER Path
            The path where the key should be exported to. Uses json if path ends with .json. Will use clixml in other cases.

        .PARAMETER AccountKey
            The account key that will be exported to the Path. If AutomaticAccountKeyHandling is enabled it will export the registered account key.

        .PARAMETER Force
            Allow the command to override an existing account key.


        .EXAMPLE
            PS> Export-AccountKey -Path "C:\myExportPath.xml" -AccountKey $myAccountKey
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(ValueFromPipeline=$true)]
        [ValidateNotNull()]
        [IAccountKey]
        $AccountKey,

        [Parameter()]
        [switch]
        $Force
    )

    process {
        $ErrorActionPreference = 'Stop';

        $AccountKey.ExportKey() | Export-AcmeObject $Path -Force:$Force
    }
}
function Import-AccountKey {
    <#
        .SYNOPSIS
            Imports an exported account key.

        .DESCRIPTION
            Imports an account key that has been exported with Export-AccountKey. If requested, the key is registered for automatic key handling.


        .PARAMETER Path
            The path where the key has been exported to.

        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER PassThru
            If set, the account key will be returned to the pipeline.


        .EXAMPLE
            PS> Import-AccountKey -State $myState -Path C:\AcmeTemp\AccountKey.xml
    #>
    param(
        # Specifies a path to one or more locations.
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Position = 0)]
        [ValidateNotNull()]
        [AcmeState]
        $State,

        [Parameter()]
        [switch]
        $PassThru
    )

    process {
        $ErrorActionPreference = 'Stop'

        $imported = Import-AcmeObject $Path

        $accountKey = [KeyFactory]::CreateAccountKey($imported);
        if($State) {
            $State.Set($accountKey);
        }

        if($PassThru -or -not $State) {
            return $accountKey;
        }
    }
}
function New-AccountKey {
    <#
        .SYNOPSIS
            Creates a new account key, that will be used to sign ACME operations.
            Provide a path where to save the key, since being able to restore it is crucial.

        .DESCRIPTION
            Creates and stores a new account key, that can be used for ACME operations.
            The key will be added to the state.


        .PARAMETER RSA
            Used to select RSA key type. (default)

        .PARAMETER RSAHashSize
            The hash size used for the RSA algorithm.

        .PARAMETER RSAKeySize
            The key size of the RSA algorithm.


        .PARAMETER ECDsa
            Used to select ECDsa key type.

        .PARAMETER ECDsaHashSize
            The hash size used for the ECDsa algorithm.


        .PARAMETER Path
            The path where the keys will be stored.


        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.
            The account key will be stored into the state, if present.

        .PARAMETER PassThru
            Forces the new account key to be returned to the pipeline, even if state is set.

        .PARAMETER Force
            If there's already a key present in the state, you need to provide the force switch to override the
            existing account key.

        .EXAMPLE
            PS> New-AccountKey -State $myState

        .EXAMPLE
            PS> New-AccountKey -State $myState -RSA -HashSize 512

        .EXAMPLE
            PS> New-AccountKey -ECDsa -HashSize 384
    #>
    [CmdletBinding(DefaultParameterSetName="RSA", SupportsShouldProcess=$true)]
    [OutputType("IAccountKey")]
    param(
        [Parameter(ParameterSetName="RSA")]
        [switch]
        $RSA,

        [Parameter(ParameterSetName="RSA")]
        [ValidateSet(256, 384, 512)]
        [int]
        $RSAHashSize = 256,

        [Parameter(ParameterSetName="RSA")]
        [ValidateSet(2048)]
        [int]
        $RSAKeySize = 2048,


        [Parameter(ParameterSetName="ECDsa")]
        [switch]
        $ECDsa,

        [Parameter(ParameterSetName="ECDsa")]
        [ValidateSet(256, 384, 512)]
        [int]
        $ECDsaHashSize = 256,

        [Parameter(Position = 0)]
        [ValidateNotNull()]
        [AcmeState]
        $State,

        [Parameter()]
        [switch]
        $PassThru,

        [Parameter()]
        [switch]
        $Force
    )

    if($PSCmdlet.ParameterSetName -eq "ECDsa") {
        $accountKey = [IAccountKey]([ECDsaAccountKey]::new($ECDsaHashSize));
        Write-Verbose "Created new ECDsa account key with hash size $ECDsaHashSize";
    } else {
        $accountKey = [IAccountKey]([RSAAccountKey]::new($RSAHashSize, $RSAKeySize));
        Write-Verbose "Created new RSA account key with hash size $RSAHashSize and key size $RSAKeySize";
    }

    if($State -and $PSCmdlet.ShouldProcess("AccountKey", "Add created account key to state.",
        "The created account key will now be added to the state object."))
    {
        if($null -eq $State.GetAccountKey() -or $Force -or
            $PSCmdlet.ShouldContinue("The existing account key will be overriden. Do you want to continue?", "Replace account key"))
        {
            $State.Set($accountKey);
        }
    }

    if($PassThru -or -not $State) {
        return $accountKey;
    }
}
function Get-Authorization {
    <#
        .SYNOPSIS
            Fetches authorizations from acme service.

        .DESCRIPTION
            Fetches all authorizations for an order or an single authorizatin by its resource url.


        .PARAMETER Order
            The order, whoose authorizations will be fetched

        .PARAMETER Url
            The authorization resource url to fetch the data.

        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.


        .EXAMPLE
            PS> Get-Authorization $myOrder $myState

        .EXAMPLE
            PS> Get-Authorization https://acme.server/authz/1243 $myState
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = "FromOrder")]
        [ValidateNotNull()]
        [AcmeOrder]
        $Order,

        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "FromUrl")]
        [ValidateNotNullOrEmpty()]
        [uri]
        $Url,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            "FromOrder" {
                $Order.AuthorizationUrls | ForEach-Object { Get-Authorization -Url $_ $State }
            }
            Default {
                $response = Invoke-SignedWebRequest $Url $State
                return [AcmeAuthorization]::new($response);
            }
        }
    }
}
function Export-Certificate {
    <#
        .SYNOPSIS
            Exports an issued certificate as pfx with private and public key.

        .DESCRIPTION
            Exports an issued certificate by downloading it from the acme service and combining it with the private key.


        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER Order
            The order which contains the issued certificate.

        .PARAMETER CertificateKey
            The key which was used to create the orders CSR.

        .PARAMETER Path
            The path where the certificate will be saved.

        .PARAMETER Password
            The password used to secure the certificate.

        .PARAMETER Force
            Allows the operation to override existing a certificate.


        .EXAMPLE
            PS> Export-Certificate -Order $myOrder -CertficateKey $myKey -Path C:\AcmeCerts\example.com.pfx
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [AcmeOrder]
        $Order,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [ICertificateKey]
        $CertificateKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string]
        $Path,

        [Parameter()]
        [SecureString]
        $Password,

        [Parameter()]
        [switch]
        $Force
    )

    $ErrorActionPreference = 'Stop'

    if(Test-Path $Path) {
        if($Force) {
            Clear-Content $Path;
        } else {
            throw "$Path does already exist."
        }
    }

    $response = Invoke-SignedWebRequest $Order.CertificateUrl $State;
    $certificate = $response.Content;

    if($PSVersionTable.PSVersion -ge "6.0") {
        $CertificateKey.ExportPfx($certificate, $Password) | Set-Content $Path -AsByteStream
    } else {
        $CertificateKey.ExportPfx($certificate, $Password) | Set-Content $Path -Encoding Byte
    }
}
function Export-CertificateKey {
    <#
        .SYNOPSIS
            Stores an certificate key to the given path.

        .DESCRIPTION
            Stores an certificate key to the given path. If the path already exists an error will be thrown and the key will not be saved.


        .PARAMETER Path
            The path where the key should be exported to. Uses json if path ends with .json. Will use clixml in other cases.

        .PARAMETER CertificateKey
            The certificate key that will be exported to the Path.


        .EXAMPLE
            PS> Export-CertificateKey -Path "C:\myExportPath.xml" -CertificateKey $myCertificateKey
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(ValueFromPipeline=$true)]
        [ValidateNotNull()]
        [ICertificateKey]
        $CertificateKey
    )

    process {
        if(Test-Path $Path) {
            throw "$Path already exists. This method will not override existing files"
        }

        if($Path -like "*.json") {
            $CertificateKey.ExportKey() | ConvertTo-Json -Compress | Out-File $Path -Encoding utf8
            Write-Verbose "Exported certificate key as JSON to $Path";
        } else {
            $CertificateKey.ExportKey() | Export-Clixml -Path $Path
            Write-Verbose "Exported certificate key as CLIXML to $Path";
        }
    }
}
function Import-CertificateKey {
    <#
        .SYNOPSIS
            Imports an exported certificate key.

        .DESCRIPTION
            Imports an certificate key that has been exported with Export-CertificateKey. If requested, the key is registered for automatic key handling.


        .PARAMETER Path
            The path where the key has been exported to.


        .EXAMPLE
            PS> Import-CertificateKey -Path C:\AcmeCertKeys\example.key.xml;
    #>
    param(
        # Specifies a path to one or more locations.
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
    )

    $ErrorActionPreference = 'Stop'

    if($Path -like "*.json") {
        $imported = Get-Content $Path -Raw | ConvertFrom-Json | ConvertTo-OriginalType;
    } else {
        $imported = Import-Clixml $Path | ConvertTo-OriginalType
    }

    $certificateKey = [KeyFactory]::CreateCertificateKey($imported);
    return $certificateKey;
}
function New-CertificateKey {
    <#
        .SYNOPSIS
            Creates a new certificate key, that can will used to sign ACME operations.
            Provide a path where to save the key, since being able to restore it is crucial.

        .DESCRIPTION
            Creates and stores a new certificate key, that can be used for ACME operations.
            The key will first be created, than exported and imported again to make sure, it has been saved.
            You can skip the export by providing the SkipExport switch.


        .PARAMETER RSA
            Used to select RSA key type. (default)

        .PARAMETER RSAHashSize
            The hash size used for the RSA algorithm.

        .PARAMETER RSAKeySize
            The key size of the RSA algorithm.


        .PARAMETER ECDsa
            Used to select ECDsa key type.

        .PARAMETER ECDsaHashSize
            The hash size used for the ECDsa algorithm.


        .PARAMETER Path
            The path where the keys will be stored.

        .PARAMETER SkipKeyExport
            Allows you to suppress the export of the certificate key.


        .EXAMPLE
            PS> New-CertificateKey -Path C:\myKeyExport.xml -AutomaticCertificateKeyHandling

        .EXAMPLE
            PS> New-CertificateKey -Path C:\myKeyExport.json -RSA -HashSize 512

        .EXAMPLE
            PS> New-CertificateKey -ECDsa -HashSize 384 -SkipKeyExport
    #>
    [CmdletBinding(DefaultParameterSetName="RSA", SupportsShouldProcess=$true)]
    [OutputType("ICertificateKey")]
    param(
        [Parameter(ParameterSetName="RSA")]
        [switch]
        $RSA,

        [Parameter(ParameterSetName="RSA")]
        [ValidateSet(256, 384, 512)]
        [int]
        $RSAHashSize = 256,

        [Parameter(ParameterSetName="RSA")]
        [int]
        $RSAKeySize = 2048,


        [Parameter(ParameterSetName="ECDsa")]
        [switch]
        $ECDsa,

        [Parameter(ParameterSetName="ECDsa")]
        [ValidateSet(256, 384, 512)]
        [int]
        $ECDsaHashSize = 256,


        [Parameter()]
        [string]
        $Path,

        [Parameter()]
        [switch]
        $SkipKeyExport
    )

    if(-not $SkipKeyExport) {
        if(-not $Path) {
            throw "Path was null or empty. Provide a path for the key to be exported or specify SkipKeyExport";
        }
    }

    if($PSCmdlet.ParameterSetName -eq "ECDsa") {
        $certificateKey = [ICertificateKey]([ECDsaCertificateKey]::new($ECDsaHashSize));
        Write-Verbose "Created new ECDsa certificate key with hash size $ECDsaHashSize";
    } else {
        if($RSAKeySize -lt 2048 -or $RSAKeySize -gt 4096 -or ($RSAKeySize%8) -ne 0) {
            throw "The RSAKeySize must be between 2048 and 4096 and must be divisible by 8";
        }

        $certificateKey = [ICertificateKey]([RSACertificateKey]::new($RSAHashSize, $RSAKeySize));
        Write-Verbose "Created new RSA certificate key with hash size $RSAHashSize and key size $RSAKeySize";
    }

    if($SkipKeyExport) {
        Write-Warning "The certificate key will not be exported. Make sure you save the certificate key!.";
        return $certificateKey;
    }

    if($PSCmdlet.ShouldProcess("CertificateKey", "Store created key to $Path and reload it from there")) {
        Export-CertificateKey -CertificateKey $certificateKey -Path $Path -ErrorAction 'Stop' | Out-Null
        return Import-CertificateKey -Path $Path -ErrorAction 'Stop'
    }
}
function Complete-Challenge {
    <#
        .SYNOPSIS
            Signals a challenge to be checked by the ACME service.

        .DESCRIPTION
            The ACME service will be called to signal, that the challenge is ready to be validated.
            The result of the operation will be returned.


        .PARAMETER Challenge
            The challenge, which is ready to be validated.

        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.


        .EXAMPLE
            PS> Complete-Challange $myState $myChallange

        .EXAMPLE
            PS> $myChallenge | Complete-Challenge $myState
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [AcmeChallenge]
        $Challenge,

        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State
    )

    process {
        $payload = @{};

        if($PSCmdlet.ShouldProcess("Challenge", "Complete challenge by submitting completion to ACME service")) {
            $response = Invoke-SignedWebRequest $Challenge.Url $State $payload;

            return [AcmeChallenge]::new($response, $Challenge.Identifier);
        }
    }
}
function Get-Challenge {
    <#
        .SYNOPSIS
            Gets the challange from the ACME service.

        .DESCRIPTION
            Gets the challange of the specified type from the specified authorization and prepares it with
            data needed to complete the challange

        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER Authorization
            The authorization for which the challange will be fetched.

        .PARAMETER Type
            The challange type to fetch. One of http-01,dns-01,tls-alpn-01


        .EXAMPLE
            PS> $myAuthorization | Get-Challange -State $myState -Type "http-01"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1)]
        [ValidateNotNull()]
        [AcmeAuthorization] $Authorization,

        [Parameter(Mandatory = $true, Position = 2)]
        [string] $Type
    )

    process {
        $challange = $Authorization.Challenges | Where-Object { $_.Type -eq $Type } | Select-Object -First 1
        if(-not $challange.Data) {
            $challange | Initialize-Challenge $State
        }

        return $challange;
    }
}
function Initialize-Challenge {
    <#
        .SYNOPSIS
            Prepares a challange with the data explaining how to complete it.

        .DESCRIPTION
            Provides the data how to resolve the challange into the challanges data property.

        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER Authorization
            The authorization of which all challanges will be initialized.

        .PARAMETER Challenge
            The challenge which should be initialized.

        .PARAMETER PassThru
            Forces the command to return the data to the pipeline.


        .EXAMPLE
            PS> Initialize-Challange $myState -Challange $challange
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1, ParameterSetName="ByAuthorization")]
        [ValidateNotNull()]
        [AcmeAuthorization] $Authorization,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1, ParameterSetName="ByChallenge")]
        [ValidateNotNull()]
        [AcmeChallenge] $Challenge,

        [Parameter()]
        [switch]
        $PassThru
    )

    process {
        if($PSCmdlet.ParameterSetName -eq "ByAuthorization") {
            return ($Authorization.challenges | Initialize-Challenge $State -PassThru:$PassThru);
        }

        $accountKey = $State.GetAccountKey();

        switch($Challenge.Type) {
            "http-01" {
                $fileName = $Challenge.Token;
                $relativePath = "/.well-known/acme-challenge/$fileName"
                $fqdn = "$($Challenge.Identifier.Value)$relativePath"
                $content = [KeyAuthorization]::Compute($AccountKey, $Challenge.Token);

                $Challenge.Data = [PSCustomObject]@{
                    "Type" = $Challenge.Type;
                    "Token" = $Challenge.Token;
                    "Filename" = $fileName;
                    "RelativeUrl" = $relativePath;
                    "AbsoluteUrl" = $fqdn;
                    "Content" = $content;
                }
            }

            "dns-01" {
                $txtRecordName = "_acme-challenge.$($Challenge.Identifier.Value)";
                $content = [KeyAuthorization]::ComputeDigest($AccountKey, $Challenge.Token);

                $Challenge.Data =  [PSCustomObject]@{
                    "Type" = "dns-01";
                    "Token" = $Challenge.Token;
                    "TxtRecordName" = $txtRecordName;
                    "Content" = $content;
                }
            }

            "tls-alpn-01" {
                $content = [KeyAuthorization]::Compute($AccountKey, $Challenge.Token);

                $Challenge.Data =  [PSCustomObject]@{
                    "Type" = $Challenge.Type;
                    "Token" = $Challenge.Token;
                    "SubjectAlternativeName" = $Challenge.Identifier.Value;
                    "AcmeValidation-v1" = $content;
                }
            }

            Default {
                throw "Cannot show how to resolve challange of unknown type $($Challenge.Type)"
            }
        }

        if($PassThru) {
            return $Challenge;
        }
    }
}
function New-Nonce {
    <#
        .SYNOPSIS
            Gets a new nonce.

        .DESCRIPTION
            Issues a web request to receive a new nonce from the service directory


        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER PassThru
            Forces the nonce to be returned to the pipeline.


        .EXAMPLE
            PS> New-Nonce -State $state
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType("string")]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate("ServiceDirectory")})]
        [AcmeState]
        $State,

        [Parameter()]
        [switch]
        $PassThru
    )

    $Url = $State.GetServiceDirectory().NewNonce;

    $response = Invoke-AcmeWebRequest $Url -Method Head
    $nonce = $response.NextNonce;

    if($response.IsError) {
        throw "$($response.ErrorMessage)`n$($response.Content)";
    }
    if(-not $nonce) {
        throw "Could not retreive new nonce";
    }

    if($PSCmdlet.ShouldProcess("Nonce", "Store new nonce into state")) {
        $State.SetNonce($nonce);
    }

    if($PassThru) {
        return $nonce;
    }
}
function Complete-Order {
    <#
        .SYNOPSIS
            Completes an order process at the ACME service, so the certificate will be issued.

        .DESCRIPTION
            Completes an order process by submitting a certificate signing request to the ACME service.


        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER Order
            The order to be completed.

        .PARAMETER CertificateKey
            The certificate key to be used to create the certificate signing request.

        .PARAMETER PassThru
            Forces the order to be returned to the pipeline.


        .EXAMPLE
            PS> Complete-Order -State $myState -Order $myOrder -CertificateKey $myCertKey
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [AcmeOrder]
        $Order,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [ICertificateKey]
        $CertificateKey,

        [Parameter()]
        [switch]
        $PassThru
    )

    process {
        $ErrorActionPreference = 'Stop';

        $dnsNames = $Order.Identifiers | ForEach-Object { $_.Value }
        if($Order.CSROptions -and -not [string]::IsNullOrWhiteSpace($Order.CSROptions.DistinguishedName)) {
            $certDN = $Order.CSROptions.DistinguishedName;
        } else {
            $certDN = "CN=$($Order.Identifiers[0].Value)"
        }

        $csr = $CertificateKey.GenerateCsr($dnsNames, $certDN);
        $payload = @{ "csr"= (ConvertTo-UrlBase64 -InputBytes $csr) }

        $requestUrl = $Order.FinalizeUrl;

        if($PSCmdlet.ShouldProcess("Order", "Finalizing order at ACME service by submitting CSR")) {
            $response = Invoke-SignedWebRequest $requestUrl $State $payload;

            $Order.UpdateOrder($response);
        }

        if($PassThru) {
            return $Order;
        }
    }
}
function Get-Order {
    <#
        .SYNOPSIS
            Fetches an order from acme service

        .DESCRIPTION
            Uses the given url to fetch an existing order object from the acme service.


        .PARAMETER Url
            The resource url of the order to be fetched.

        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.


        .EXAMPLE
            PS> Get-Order -Url "https://service.example.com/kid/213/order/123"
    #>
    [CmdletBinding()]
    [OutputType("AcmeOrder")]
    param(
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "FromUrl")]
        [ValidateNotNullOrEmpty()]
        [uri]
        $Url,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State
    )

    $response = Invoke-SignedWebRequest $Url $State;
    return [AcmeOrder]::new($response);
}
function New-Identifier {
    <#
        .SYNOPSIS
            Creates a new identifier.

        .DESCRIPTION
            Creates a new identifier needed for orders and authorizations


        .PARAMETER Type
            The identifier type

        .PARAMETER Value
            The value of the identifer, e.g. the FQDN.


        .EXAMPLE
            PS> New-Identifier www.example.com
    #>
    [CmdletBinding(SupportsShouldProcess=$false)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        "PSUseShouldProcessForStateChangingFunctions", "", Scope="Function", Target="*")]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Value,

        [Parameter(Position = 1, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Type = "dns"
    )

    process {
        return [AcmeIdentifier]::new($Type, $Value);
    }
}
function New-Order {
    <#
        .SYNOPSIS
            Creates a new order object.

        .DESCRIPTION
            Creates a new order object to be used for signing a new certificate including all submitted identifiers.


        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER Identifiers
            The list of identifiers, which will be covered by the certificates subject alternative names.

        .PARAMETER NotBefore
            Earliest date the certificate should be considered valid.

        .PARAMETER NotAfter
            Latest date the certificate should be considered valid.

        .PARAMETER CertDN
            If set, this will be used as Distinguished Name for the CSR that will be send to the ACME service by Complete-Order.
            If not set, the first identifier will be used as CommonName (CN=Identifier).
            Make sure to provide a valid X500DistinguishedName.

        .EXAMPLE
            PS> New-Order -Directory $myDirectory -AccountKey $myAccountKey -KeyId $myKid -Nonce $myNonce -Identifiers $myIdentifiers

        .EXAMPLE
            PS> New-Order -Identifiers (New-Identifier "dns" "www.test.com")
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [AcmeIdentifier[]] $Identifiers,

        [Parameter()]
        [System.DateTimeOffset] $NotBefore,

        [Parameter()]
        [System.DateTimeOffset] $NotAfter,

        [Parameter()]
        [string] $CertDN
    )

    $payload = @{
        "identifiers" = @($Identifiers | Select-Object @{N="type";E={$_.Type}}, @{N="value";E={$_.Value}})
    };

    if($NotBefore -and $NotAfter) {
        $payload.Add("notBefore", $NotBefore.ToString("o"));
        $payload.Add("notAfter", $NotAfter.ToString("o"));
    }

    $requestUrl = $State.GetServiceDirectory().NewOrder;
    $csrOptions = [AcmeCsrOptions]::new()

    if(-not [string]::IsNullOrWhiteSpace($CertDN)) {
        try {
            [X500DistinguishedName]::new($CertDN) | Out-Null;
        } catch {
            throw "'$CertDN' is not a valid X500 distinguished name";
        }

        $csrOptions.DistinguishedName = $CertDN;
    } else {
        $csrOptions.DistinguishedName = "CN=$($Identifiers[0].Value)";
    }

    if($PSCmdlet.ShouldProcess("Order", "Create new order with ACME Service")) {
        $response = Invoke-SignedWebRequest $requestUrl $State $payload;

        $order = [AcmeOrder]::new($response, $csrOptions);
        $state.AddOrder($order);

        return $order;
    }
}
function Update-Order {
    <#
        .SYNOPSIS
            Updates an order from acme service

        .DESCRIPTION
            Updates the given order instance by querying the acme service.
            The result will be used to update the order stored in the state object


        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER Order
            The order to be updated.

        .PARAMETER PassThru
            Forces the updated order to be returned to the pipeline.


        .EXAMPLE
            PS> $myOrder | Update-Order -State $myState -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType("AcmeOrder")]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [ValidateScript({$_.Validate()})]
        [AcmeState]
        $State,

        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [AcmeOrder]
        $Order,

        [Parameter()]
        [switch]
        $PassThru
    )

    if($PSCmdlet.ShouldProcess("Order", "Get updated order form ACME service and store it to state")) {
        $response = Invoke-SignedWebRequest $Order.ResourceUrl $State;
        $Order.UpdateOrder($response);
        $State.SetOrder($Order);

        if($PassThru) {
            return $Order;
        }
    }
}
function Get-ServiceDirectory {
    <#
        .SYNOPSIS
            Fetches the ServiceDirectory from an ACME Servers.

        .DESCRIPTION
            This will issue a web request to either the url or to a well-known ACME server to fetch the service directory.
            Alternatively the directory can be loaded from a path, when it has been stored with Export-CliXML or as Json.


        .PARAMETER ServiceName
            The Name of an Well-Known ACME service provider.

        .PARAMETER DirectoryUrl
            Url of an ACME Directory.

        .PARAMETER Path
            Path to load the Directory from. The given file needs to be .json or .xml (CLI-Xml)

        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.

        .PARAMETER PassThru
            Forces the service directory to be returned to the pipeline.


        .EXAMPLE
            PS> Get-ServiceDirectory $myState

        .EXAMPLE
            PS> Get-ServiceDirectory "LetsEncrypt" $myState -PassThru

        .EXAMPLE
            PS> Get-ServiceDirectory -DirectoryUrl "https://acme-staging-v02.api.letsencrypt.org" $myState
    #>
    [CmdletBinding(DefaultParameterSetName="FromName")]
    [OutputType("ACMEDirectory")]
    param(
        [Parameter(Position=1, ParameterSetName="FromName")]
        [string]
        $ServiceName = "LetsEncrypt-Staging",

        [Parameter(Mandatory=$true, ParameterSetName="FromUrl")]
        [Uri]
        $DirectoryUrl,

        [Parameter(Mandatory=$true, ParameterSetName="FromPath")]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [AcmeState]
        $State,

        [Parameter()]
        [switch]
        $PassThru
    )

    begin {
        $KnownEndpoints = @{
            "LetsEncrypt-Staging"="https://acme-staging-v02.api.letsencrypt.org";
            "LetsEncrypt"="https://acme-v02.api.letsencrypt.org"
        }
    }

    process {
        $ErrorActionPreference = 'Stop';

        if($PSCmdlet.ParameterSetName -in @("FromName", "FormUrl")) {
            if($PSCmdlet.ParameterSetName -eq "FromName") {
                $acmeBaseUrl = $KnownEndpoints[$ServiceName];
                if($null -eq $acmeBaseUrl) {
                    $knownNames = $KnownEndpoints.Keys -join ", "
                    Write-Error "The ACME-Service-Name $ServiceName is not known. Known names are $knownNames.";
                    return;
                }

                $serviceDirectoryUrl = "$acmeBaseUrl/directory"
            } elseif ($PSCmdlet.ParameterSetName -eq "FromUrl") {
                $serviceDirectoryUrl = $DirectoryUrl
            }

            $response = Invoke-WebRequest $serviceDirectoryUrl -UseBasicParsing;

            $result = [AcmeDirectory]::new(($response.Content | ConvertFrom-Json));
            $result.ResourceUrl = $serviceDirectoryUrl;
        }

        if($PSCmdlet.ParameterSetName -eq "FromPath") {
            if($Path -like "*.json") {
                $result = [ACMEDirectory](Get-Content $Path | ConvertFrom-Json)
            } else {
                $result = [AcmeDirectory](Import-Clixml $Path)
            }
        }

        $State.Set($result);

        if($PassThru) {
            return $result;
        }
    }
}
function Get-TermsOfService {
    <#
        .SYNOPSIS
            Show the ACME service TOS

        .DESCRIPTION
            Show the ACME service TOS


        .PARAMETER State
            The state object, that is used in this module, to provide easy access to the ACME service directory,
            your account key, the associated account and the replay nonce.


        .EXAMPLE
            PS> Get-TermsOfService -State $state
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [AcmeState]
        $State
    )

    process {
        Start-Process $State.GetServiceDirectory().Meta.TermsOfService;
    }
}
function Get-State {
    <#
        .SYNOPSIS
            Initializes state from saved date.

        .DESCRIPTION
            Initializes state from saved data.
            Use this if you already have an exported account key and an account.


        .PARAMETER Path
            Path to an exported service directory

        .EXAMPLE
            PS> Initialize-AutomaticHandlers C:\myServiceDirectory.xml C:\myKey.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
    )

    $ErrorActionPreference = 'Stop';

    Write-Verbose "Loading ACME-PS state from $Path";
    $state = [AcmeState]::FromPath($Path);
    return $state;
}
function New-State {
    <#
        .SYNOPSIS
            Initializes a new state object.

        .DESCRIPTION
            Initializes a new state object, that will be used by other functions
            to access the service directory, nonce, account and account key.


        .PARAMETER Path
            Directory where the state will be persisted.

        .EXAMPLE
            PS> New-State
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter()]
        [string]
        $Path
    )

    process {
        if(-not $Path) {
            Write-Warning "You did not provide a persistency path. State will not be saved automatically."
            return [AcmeState]::new()
        } else {
            if($PSCmdlet.ShouldProcess("State", "Create new state and save it to $Path")) {
                return [AcmeState]::new($Path, $true);
            }
        }
    }
}
