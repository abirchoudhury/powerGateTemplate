$dsDiag.Clear()
#$dsDiag.ShowLog()

function Get-BomRows($entity) {
    
    $etype = $entity._EntityTypeID
    if ($etype -eq $null) { return @() }
    if ($etype -eq "File") {
        #if($entity._FullPath -eq $null) { return @() } #due to a bug in the beta version.
        if ($entity._Extension -eq 'ipt') { 
            if ($entity.'Raw Quantity' -gt 0 -and $entity.'Raw Number' -ne "") {
                $rawMaterial = New-Object PsObject -Property @{'Part Number' = $entity.'Raw Number'; '_PartNumber' = $entity.'Raw Number'; 'Name' = $entity.'Raw Number'; '_Name' = $entity.'Raw Number'; 'Number' = $entity.'Raw Number'; '_Number' = $entity.'Raw Number'; 'Bom_Number' = $entity.'Raw Number'; 'Bom_Quantity' = $entity.'Raw Quantity'; 'Bom_Position' = '1'; 'Bom_PositionNumber' = '1' }
                return @($rawMaterial)
            }
            return @()
        }
        $bomRows = Get-VaultFileBom -File $entity._FullPath -GetChildrenBy LatestVersion
    }
    else {
        if ($entity._Category -eq 'Part') { return @() }
        $bomRows = Get-VaultItemBom -Number $entity._Number
    }
    
    foreach ($bomRow in $bomRows) {
        if ($bomRow.Bom_XrefTyp -eq "Internal") {
            #virtual component
            Add-Member -InputObject $bomRow -Name "_Name" -Value $bomRow.'Bom_Part Number' -MemberType NoteProperty -Force
            Add-Member -InputObject $bomRow -Name "Part Number" -Value $bomRow.'Bom_Part Number' -MemberType NoteProperty -Force
            Add-Member -InputObject $bomRow -Name "_PartNumber" -Value $bomRow.'Bom_Part Number' -MemberType NoteProperty -Force
            Add-Member -InputObject $bomRow -Name "_Number" -Value $bomRow.'Bom_Part Number' -MemberType NoteProperty -Force
            Add-Member -InputObject $bomRow -Name "Number" -Value $bomRow.'Bom_Part Number' -MemberType NoteProperty -Force
        }
    }
    return $bomRows
}									

function Check-Items($entities) {
    foreach ($entity in $entities) {
        if ($entity._EntityTypeID -eq "File") {
            $number = $entity._PartNumber
        }
        else {
            $number = $entity._Number
        }
        if ($null -eq $number -or $number -eq "") {
            Update-BomWindowEntity $entity -Status "Error" -Tooltip "Number empty!!"
            continue
        }
        $material = GetErpMaterial -number $number
        if ($material) {
            $differences = CompareProperties -material $material -vaultEntity $entity
            if ($differences) {
                Update-BomWindowEntity $entity -Status "Different" -Tooltip $differences
            }
            else {
                Update-BomWindowEntity $entity -Status "Identical" -Tooltip ""
            }
        }
        else {
            Update-BomWindowEntity $entity -Status "New" -Tooltip "Item does not exist in ERP. Will be created."
        }
    }
}
function Transfer-Items($entities) {
    foreach ($entity in $entities) {
        if ($entity._Status -eq "New") {
            $newMaterial = NewMaterial
            $newMaterial = PrepareMaterial -material $newMaterial -vaultEntity $entity
            $material = CreateMaterialBase -material $newMaterial
            if ($material) {
                Update-BomWindowEntity $entity -Status "Identical" -Properties $entity
            }
            else {
                Update-BomWindowEntity $entity -Status "Error" -Toolipt $material._ErrorMessage
            }
        }
        elseif ($entity._Status -eq "Different") {
            $material = NewMaterial
            $material = PrepareMaterial -material $material -vaultEntity $entity
            $material = UpdateMaterialBase -material $material
            if ($material) {
                Update-BomWindowEntity $entity -Status "Identical"
            }
            else {
                Update-BomWindowEntity $entity -Status "Error" -Toolipt $material._ErrorMessage
            }
        }
        else {
            Update-BomWindowEntity $entity -Status $entity._Status
        }
    }
}

function GetNumberFromEntity($entity) {
    if ($entity._EntityTypeID -eq "FILE") {
        $number = $entity._PartNumber
    }
    else {
        $number = $entity._Number
    }
    return $number
}

function Check-Boms($bomHeaders) {
    foreach ($bomHeader in $bomHeaders) {
        $number = GetNumberFromEntity -entity $bomHeader
        $erpBom = GetBomHeader -number $number
        if ($erpBom -eq $false) {
            Update-BomWindowEntity $bomHeader -Status "New" -Tooltip "BOM does not exist in ERP. Will be created!"
            foreach ($bomRow in $bomHeader.Children) {
                Update-BomWindowEntity $bomRow -Status "New" -Tooltip "Position will be added to ERP"
            }
        }
        else {
            Update-BomWindowEntity $bomHeader -Status "Identical" -Tooltip "BOM is identical between Vault and ERP"
            foreach ($bomRow in $bomHeader.Children) {
                $number = GetNumberFromEntity -entity $bomRow
                $erpRow = $erpBom.BomRows | Where-Object { $_.ChildNumber -eq $number -and $_.Position -eq $bomRow.Bom_PositionNumber }
                if ($null -ne $erpRow) {
                    if ($bomRow.Bom_Quantity -eq $erpRow.Quantity) {
                        Update-BomWindowEntity $bomRow -Status "Identical" -Tooltip "Position is identical"
                    }
                    else {
                        Update-BomWindowEntity $bomRow -Status "Different" -Tooltip "Quantity is different: '$($bomRow.Bom_Quantity) <> $($erpRow.Quantity)'"
                        Update-BomWindowEntity $bomHeader -Status "Different" -Tooltip "BOMs are different between Vault and ERP!"
                    }
                }
                else {
                    Update-BomWindowEntity $bomRow -Status "New" -Tooltip "Position will be added to ERP"
                    Update-BomWindowEntity $bomHeader -Status "Different" -Tooltip "BOMs are different between Vault and ERP!"
                }
            }
            foreach ($erpRow in $erpBom.BomRows) {
                $bomRow = $bomHeader.Children | Where-Object { $_._PartNumber -eq $erpRow.ChildNumber -and $_.Bom_PositionNumber -eq $erpRow.Position }
                if ($null -eq $bomRow) {
                    $remove = Add-BomWindowEntity -Type BomRow -Properties @{'Bom_Number' = $erpRow.ChildNumber; 'Name' = $erpRow.ChildNumber; 'Bom_Name' = $erpRow.ChildNumber; '_Name' = $erpRow.ChildNumber; 'Bom_Quantity' = $erpRow.Quantity; 'Bom_PositionNumber' = $erpRow.Position } -Parent $bomHeader
                    Update-BomWindowEntity $remove -Status "Remove" -Tooltip "Position will be deleted in ERP"
                    Update-BomWindowEntity $bomHeader -Status "Different" -Tooltip "BOMs are different between Vault and ERP!"
                }
            }
        }
    }
}

function Transfer-Boms($bomHeaders) {
    foreach ($bomHeader in $bomHeaders) {
        $parentNumber = GetNumberFromEntity -entity $bomHeader
        if ($bomHeader._Status -eq "New") {
            $newBomRows = @()
            foreach ($bomRow in $bomHeader.Children) {
                $newBomRow = NewBomRow
                $newBomRow.ParentNumber = $parentNumber
                $newBomRow.ChildNumber = $bomRow._PartNumber
                $newBomRow.Position = $bomRow.Bom_PositionNumber
                $newBomRow.Quantity = $bomRow.Bom_Quantity
                $newBomRows += $newBomRow
            }
            $newBomHeader = NewBomHeader
            $newBomHeader.Number = $parentNumber
            $newBomHeader.Description = $bomHeader.Title
            $newBomHeader.BomRows = $newBomRows
            $newBomHeader = CreateBomHeader -newBomHeader $newBomHeader
            if ($newBomHeader) {
                $dsDiag.Trace("new bom row")
                Update-BomWindowEntity $bomHeader -Status "Identical"
                foreach ($bomRow in $bomHeader.Children) {
                    Update-BomWindowEntity $bomRow -Status "Identical" -Tooltip ""
                }
            }
            else {
                Update-BomWindowEntity $bomHeader -Status "Error" -Tooltip $newBomHeader._ErrorMessage
                foreach ($bomRow in $bomHeader.Children) {
                    Update-BomWindowEntity $bomRow -Status "Error" -Tooltip $newBomHeader._ErrorMessage
                }
            }
        }
        elseif ($bomHeader._Status -eq "Different") {
            $bomHeaderStatus = "Identical"
            foreach ($bomRow in $bomHeader.Children) {
                $childNumber = GetNumberFromEntity -entity $bomRow

                if ($bomRow._Status -eq "New") {
                    $newBomRow = NewBomRow
                    $newBomRow.ParentNumber = $parentNumber
                    $newBomRow.ChildNumber = $childNumber
                    $newBomRow.Position = $bomRow.Bom_PositionNumber
                    $newBomRow.Quantity = $bomRow.Bom_Quantity
                    $newBomRow = CreateBomRow -newBomRow $newBomRow
                    if ($newBomRow) {
                        Update-BomWindowEntity $bomRow -Status "Identical" -Tooltip ""
                    }
                    else {
                        Update-BomWindowEntity $bomRow -Status "Error" -Tooltip $newBomRow._ErrorMessage
                        $bomHeaderStatus = "Error"
                    }
                }
                elseif ($bomRow._Status -eq "Different") {
                    $updateBomRow = GetBomRow -parentNumber $parentNumber -childNumber $childNumber -position $bomRow.Bom_PositionNumber
                    $updateBomRow.Quantity = $bomRow.Bom_Quantity
                    $updateBomRow = UpdateBomRow -updateBomRow $updateBomRow
                    if ($updateBomRow) {
                        Update-BomWindowEntity $bomRow -Status "Identical" -Tooltip ""
                    }
                    else {
                        Update-BomWindowEntity $bomRow -Status "Error" -Tooltip $updateBomRow._ErrorMessage
                        $bomHeaderStatus = "Error"
                    }
                }
                elseif ($bomRow._Status -eq "Remove") {
                    $removeBomRow = RemoveBomRow -parentNumber $parentNumber -childNumber $bomRow.Bom_Number -position $bomRow.Bom_PositionNumber
                    if ($removeBomRow) {
                        Update-BomWindowEntity $bomRow -Status "Identical" -Tooltip ""
                    }
                    else {
                        Update-BomWindowEntity $bomRow -Status "Error" -Tooltip $removeBomRow._ErrorMessage
                        $bomHeaderStatus = "Error"
                    }
                }
                else {
                    Update-BomWindowEntity $bomRow -Status $bomRow._Status
                }
            }
            Update-BomWindowEntity $bomHeader -Status $bomHeaderStatus
        }
        else {
            Update-BomWindowEntity $bomHeader -Status $bomHeader._Status
            foreach ($bomRow in $bomHeader.Children) {
                Update-BomWindowEntity $bomRow -Status $bomRow._Status
            }
        }
    }
}

$vaultContext.ForceRefresh = $true
$id = $vaultContext.CurrentSelectionSet[0].Id
if ($vaultContext.CurrentSelectionSet[0].TypeId.EntityClassId -eq "FILE") {
    $entity = Get-VaultFile -FileId $id
}
else {
    $entity = Get-VaultItem -ItemId $id
}

Show-BomWindow -Entity $entity