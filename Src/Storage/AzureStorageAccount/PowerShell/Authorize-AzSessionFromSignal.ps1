function Authorize-AzSessionFromSignal {
    param (
        [Parameter(Mandatory)][Signal]$Signal
    )

    $opSignal = [Signal]::Start("Authorize-AzSession", $Signal) | Select-Object -Last 1

    try {
        # ░▒▓█ RESOLVE AUTH MODE FROM GRAPH █▓▒░
        $authModeSignal = Resolve-PathFromDictionary -Dictionary $Signal -Path "$.#.@.Authorization.Mode" | Select-Object -Last 1
        $opSignal.MergeSignal($authModeSignal)

        if ($authModeSignal.Failure()) {
            return $opSignal.LogCritical("❌ Authorization.Mode is not defined in the Graph.")
        }

        $authMode = $authModeSignal.GetResult()
        $sessionSignal = $null

        switch ($authMode.ToLower()) {
            "managed" {
                Connect-AzAccount -Identity | Out-Null
                $sessionSignal = [Signal]::Start("AzAuth.Managed") | Select-Object -Last 1
                $sessionSignal.SetResult("ManagedIdentity")
            }

            "interactive" {
                Connect-AzAccount | Out-Null
                $sessionSignal = [Signal]::Start("AzAuth.Interactive") | Select-Object -Last 1
                $sessionSignal.SetResult("InteractiveLogin")
            }

            "serviceprincipal" {
                $tenantSignal     = Resolve-PathFromDictionary -Dictionary $Signal -Path "$.#.@.Authorization.TenantId" | Select-Object -Last 1
                $clientIdSignal   = Resolve-PathFromDictionary -Dictionary $Signal -Path "$.#.@.Authorization.ClientId" | Select-Object -Last 1
                $secretSignal     = Resolve-PathFromDictionary -Dictionary $Signal -Path "$.#.@.Authorization.ClientSecret" | Select-Object -Last 1

                $opSignal.MergeSignal(@($tenantSignal, $clientIdSignal, $secretSignal))

                if ($opSignal.MergeSignalAndVerifyFailure(@($tenantSignal, $clientIdSignal, $secretSignal))) {
                    return $opSignal.LogCritical("❌ Missing required ServicePrincipal fields in Authorization block.")
                }

                $tenantId    = $tenantSignal.GetResult()
                $clientId    = $clientIdSignal.GetResult()
                $clientSecret = $secretSignal.GetResult() | ConvertTo-SecureString -AsPlainText -Force
                $creds       = [PSCredential]::new($clientId, $clientSecret)

                Connect-AzAccount -ServicePrincipal -Tenant $tenantId -Credential $creds | Out-Null

                $sessionSignal = [Signal]::Start("AzAuth.ServicePrincipal") | Select-Object -Last 1
                $sessionSignal.SetResult("ServicePrincipal")
            }

            default {
                return $opSignal.LogCritical("❌ Unknown Authorization.Mode: '$authMode'")
            }
        }

        # ░▒▓█ REGISTER AUTH SIGNAL IN GRAPH █▓▒░
        $registerSignal = Add-PathToDictionary -Dictionary $Signal -Path "$.#.@.Authorization.AzSession" -Value $sessionSignal | Select-Object -Last 1
        $opSignal.MergeSignal($registerSignal)

        if ($registerSignal.Failure()) {
            return $opSignal.LogCritical("❌ Failed to register AzSession in Graph.")
        }

        $opSignal.SetResult($sessionSignal)
        $opSignal.LogInformation("🔐 Azure session authorized using mode: $authMode")
    }
    catch {
        $opSignal.LogCritical("🔥 Exception during Azure authorization: $($_.Exception.Message)")
    }

    return $opSignal
}
