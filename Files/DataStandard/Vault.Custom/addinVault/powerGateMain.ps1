$commonModulePath = $PSScriptRoot.Replace('\Vault.Custom\addinVault', '\powerGateModules')
$addinPath = $PSScriptRoot
$modules = Get-ChildItem -path $commonModulePath -Filter *.psm1
$modules | ForEach-Object { Import-Module -Name $_.FullName -Global }	

ConnectToErpServer

function OnTabContextChanged_powerGate($xamlFile) {
	if ($xamlFile -eq "erpItem.xaml") {
		InitMaterialTab
	}
	elseif ($xamlFile -eq "erpBom.xaml") {
		InitBomTab
	}
	elseif ($xamlFile -eq "erpSearch.xaml") {
		InitSearchTab
	}
}

function GetSelectedObject {
	$entity = $null
	if ($VaultContext.SelectedObject.TypeId.SelectionContext -eq "FileMaster") {
		$entity = Get-VaultFile -FileId $vaultContext.SelectedObject.Id
	}
	elseif ($VaultContext.SelectedObject.TypeId.SelectionContext -eq "ItemMaster") {
		$entity = Get-VaultItem -ItemId $vaultContext.SelectedObject.Id
	}
	return $entity
}

function GetEntityNumber($entity) {
	if ($entity._EntityTypeID -eq "FILE") {
		$number = $entity._PartNumber
	}
	else {
		$number = $entity._Number
	}
	return $number
}

function InitMaterialTab {
	$entity = GetSelectedObject
	ActivateMaterialSection
	SetMaterialSelectionLists
	RegisterUiEvents
	$dswindow.FindName("ViewMaterial").DataContext = $null
	$number = GetEntityNumber -entity $entity
	$material = GetErpMaterial -number $number
	if ($material) {
		$dswindow.FindName("ViewMaterial").DataContext = $material
		ActivateMaterialSection -section "View"
	}
	else {
		$material = NewMaterial
		$material = PrepareMaterial -material $material -vaultEntity $entity
		$dswindow.FindName("NewMaterial").DataContext = $material
		ActivateMaterialSection -section "New"
	}
}

function PrepareMaterial($material, $vaultEntity) {
	[xml]$cfg = $vault.KnowledgeVaultService.GetVaultOption("powerGateConfig")
	$mappings = Select-Xml -Xml $cfg -XPath "//VaultPropertyMappings" 
	foreach ($mapping in $mappings.Node.ChildNodes) {
		if ($mapping.NodeType -eq "Comment") { continue }
		if ($material.PsObject.Properties.Name -notcontains $mapping.Key ) { 
			$dsDiag.Trace("property '$($mapping.Key)' not found on material. Check the config file")
			continue 
		}
		$dsDiag.Trace("apply initial mapped value: $($mapping.Key) = $($mapping.Value)")
		$material.$($mapping.Key) = $vaultEntity.$($mapping.Value)
	}
	return $material
}

function CompareProperties($material, $vaultEntity) {
	[xml]$cfg = $vault.KnowledgeVaultService.GetVaultOption("powerGateConfig")
	$mappings = Select-Xml -Xml $cfg -XPath "//VaultPropertyMappings" 
	$differences = @()
	foreach ($mapping in $mappings.Node.ChildNodes) {
		if ($mapping.NodeType -eq "Comment") { continue }
		if ($material.$($mapping.Key) -ne $vaultEntity.$($mapping.Value)) {
			$differences += "ERP: $($material.$($mapping.Key)) <> V: $($vaultEntity.$($mapping.Value))"
		}
	}
	return $differences -join '\n'
}

function InitBomTab {
	$entity = GetSelectedObject
	$number = GetEntityNumber -entity $entity
	$bom = GetBomHeader -number $number
	$dswindow.FindName("BOMGrid").DataContext = $bom
}

function InitSearchTab {
	InitSearch
}

function SetEntityNumber($number) {
	if ($VaultContext.SelectedObject.TypeId.SelectionContext -eq "FileMaster") {
		$file = Get-VaultFile -FileId $vaultContext.SelectedObject.Id
		Update-VaultFile -File $file._FullPath -Properties @{"Part Number" = $number }
	}
	elseif ($VaultContext.SelectedObject.TypeId.SelectionContext -eq "ItemMaster") {
		$item = Get-VaultItem -ItemId $vaultContext.SelectedObject.Id
		Update-VaultItem -Number $item._Number -NewNumber $number
	}
}

function CreateMaterial {
	$newMaterial = $dswindow.FindName("NewMaterial").DataContext
	$newMaterial = CreateMaterialBase -material $newMaterial
	SetEntityNumber -number $newMaterial.Number
	[System.Windows.Forms.SendKeys]::SendWait("{F5}")
}

function UpdateMaterial {
	$material = $dswindow.FindName("ViewMaterial").DataContext
	$material = UpdateMaterialBase -material $material
	if ($material) {
		Show-MessageBox -message "Update successful" -icon "Information" 
	} 
	else {
		Show-MessageBox -message $material._ErrorMessage -icon "Error" -title "ERP material update error"
	}
	InitMaterialTab
}

function LinkMaterial {
	$material = $dsWindow.FindName("SearchResults").SelectedItem
	$number = $material.Number
	if ($number) {
		$answer = [System.Windows.Forms.MessageBox]::Show("Do you really want to link the item '$number'?", "Link ERP item", "YesNo", "Question")	
		if ($answer -eq "Yes") {
			SetEntityNumber -number $number
			[System.Windows.Forms.SendKeys]::SendWait("{F5}")
		}
	}
}