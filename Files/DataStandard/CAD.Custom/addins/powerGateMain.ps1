$commonModulePath = $PSScriptRoot.Replace('\CAD.Custom\addins', '\powerGateModules')
$modules = Get-ChildItem -path $commonModulePath -Filter *.psm1
$modules | ForEach-Object { Import-Module -Name $_.FullName -Global }	

ConnectToErpServer

function InitializeWindow_powerGate {
	$dsDiag.Clear()
	#$dsDiag.ShowLog()
	InitMaterial
	InitSearch
}

function InitMaterial {
	SetMaterialSelectionLists
	RegisterUiEvents
	RegisterLocalUiEvents
	ResetMaterialView
}

function ResetMaterialView {
	ActivateMaterialSection
	$dswindow.FindName("ViewMaterial").DataContext = $null
	$material = GetErpMaterial -number $prop["Part Number"].Value
	if ($material) {
		$dswindow.FindName("ViewMaterial").DataContext = $material
		ActivateMaterialSection -section "View"
	}
	else {
		$material = NewMaterial
		$material = PrepareMaterial -material $material
		$dswindow.FindName("NewMaterial").DataContext = $material
		ActivateMaterialSection -section "New"
	}
}

function PrepareMaterial($material) {
	[xml]$cfg = $vault.KnowledgeVaultService.GetVaultOption("powerGateConfig")
	$mappings = Select-Xml -Xml $cfg -XPath "//InventorPropertyMappings" 
	foreach ($mapping in $mappings.Node.ChildNodes) {
		if ($mapping.NodeType -eq "Comment") { continue }
		if ($material.PsObject.Properties.Name -notcontains $mapping.Key ) { 
			$dsDiag.Trace("property '$($mapping.Key)' not found on material. Check the config file")
			continue 
		}
		$dsDiag.Trace("apply initial mapped value: $($mapping.Key) = $($mapping.Value)")
		$material.$($mapping.Key) = $prop[$mapping.Value].Value
	}
	return $material
}

function SaveMaterialDataToInventor($material) {
	[xml]$cfg = $vault.KnowledgeVaultService.GetVaultOption("powerGateConfig")
	$mappings = Select-Xml -Xml $cfg -XPath "//InventorPropertyMappings" 
	foreach ($mapping in $mappings.Node.ChildNodes) {
		if ($mapping.NodeType -eq "Comment") { continue }
		if ($material.PsObject.Properties.Name -notcontains $mapping.Key ) { 
			$dsDiag.Trace("property '$($mapping.Key)' not found on material. Check the config file")
			continue 
		}
		$dsDiag.Trace("write to iProperty: $($mapping.Value) = $($mapping.Key)")
		$prop[$mapping.Value].Value = $material.$($mapping.Key)
	}
	return $material
}

function CreateMaterial {
	$newMaterial = $dswindow.FindName("NewMaterial").DataContext
	$newMaterial = CreateMaterialBase -material $newMaterial
	#$prop["Part Number"].Value = $newMaterial.Number
	SaveMaterialDataToInventor -material $newMaterial
	$dswindow.FindName("MainTab").IsSelected = $true
}

function UpdateMaterial {
	$material = $dswindow.FindName("ViewMaterial").DataContext
	$material = UpdateMaterialBase -material $material
	if ($material) {
		Show-MessageBox -message "Update successful" -icon "Information" 
		SaveMaterialDataToInventor -material $material
	} 
	else {
		Show-MessageBox -message $material._ErrorMessage -icon "Error" -title "ERP material update error"
	}

	ResetMaterialView
}

function RegisterLocalUiEvents {
	$Prop["Part Number"].add_PropertyChanged( {
			param( $parameter, $source)
			if ($source.PropertyName -eq "Value") {
				ResetMaterialView
			}
		})
}

function InsertMaterial {
	$fileName = $prop["_FileName"].Value
	$material = $dsWindow.FindName("SearchResults").SelectedItem
	if ($null -eq $material) { return }
	$number = $material.Number
	if ($fileName.ToLower().EndsWith(".iam")) {
		$matrix = $Application.TransientGeometry.CreateMatrix()
		$occur = $Document.ComponentDefinition.Occurrences
		$occur.AddVirtual($number, $matrix)
		[System.Windows.Forms.MessageBox]::Show("Virtual component '$number' added.", "Adding virtual component", "OK", "Info")
	}

	if ($fileName.ToLower().EndsWith(".ipt")) {
		$prop["Raw_Number"].Value = $number
		$prop["Raw_Quantity"].Value = 1
		[System.Windows.Forms.MessageBox]::Show("Raw material '$number' added.", "Adding raw material", "OK", "Info")
		$dswindow.FindName("MainTab").IsSelected = $true
	}
}