<#
.SYNOPSIS
READ-ONLY. Extract CLI type metadata from package assemblies without loading them.
.DESCRIPTION
PowerShell 7. Owning reference: ../references/release-process.md. PEReader reads
bytes and metadata tables only. No Assembly.Load, runtime reflection over a target,
constructor invocation or target IL execution. Returns public types, enum constants
and base names for generic feature-subclass discovery.
.EXAMPLE
. ./Release.Metadata.ps1
Read-ReleaseAssemblyMetadata -Path $assembly
#>
#Requires -Version 7.0
function Get-ReleaseTypeName {
    param($Reader,$Handle)
    if ($Handle.IsNil) { return $null }
    $entity=[System.Reflection.Metadata.EntityHandle]$Handle
    switch ([string]$entity.Kind) {
        TypeDefinition {
            $type=$Reader.GetTypeDefinition([System.Reflection.Metadata.TypeDefinitionHandle]$Handle)
            $parent=$type.GetDeclaringType()
            if (-not $parent.IsNil) { return (Get-ReleaseTypeName $Reader $parent)+'+'+$Reader.GetString($type.Name) }
        }
        TypeReference { $type=$Reader.GetTypeReference([System.Reflection.Metadata.TypeReferenceHandle]$Handle) }
        default { return '<type-specification>' }
    }
    $ns=$Reader.GetString($type.Namespace); $name=$Reader.GetString($type.Name)
    if ($ns) { return $ns+'.'+$name }; return $name
}
function Read-ReleaseAssemblyMetadata {
    param([Parameter(Mandatory)][string]$Path)
    $stream=[IO.File]::OpenRead($Path)
    $pe=[System.Reflection.PortableExecutable.PEReader]::new($stream)
    try {
        $reader=[System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($pe)
        $assembly=$reader.GetAssemblyDefinition()
        $types=[Collections.Generic.List[object]]::new()
        foreach ($handle in $reader.TypeDefinitions) {
            $type=$reader.GetTypeDefinition($handle)
            $visibility=([int]$type.Attributes -band 7)
            $base=Get-ReleaseTypeName $reader $type.BaseType
            $constants=@()
            if ($base -eq 'System.Enum') {
                foreach ($fieldHandle in $type.GetFields()) {
                    $field=$reader.GetFieldDefinition($fieldHandle)
                    if ($field.GetDefaultValue().IsNil) { continue }
                    $constant=$reader.GetConstant($field.GetDefaultValue())
                    $blob=$reader.GetBlobReader($constant.Value)
                    $value=switch ([string]$constant.TypeCode) {
                        Int32 { $blob.ReadInt32() }; Int16 { $blob.ReadInt16() }; Int64 { $blob.ReadInt64() }
                        UInt32 { $blob.ReadUInt32() }; UInt16 { $blob.ReadUInt16() }; Byte { $blob.ReadByte() }
                        default { '<'+[string]$constant.TypeCode+'>' }
                    }
                    $constants+=@{name=$reader.GetString($field.Name);value=$value}
                }
            }
            $types.Add(@{name=(Get-ReleaseTypeName $reader $handle);base=$base;public=($visibility -in 1,2);constants=$constants})
        }
        return @{name=$reader.GetString($assembly.Name);version=$assembly.Version.ToString();types=$types.ToArray()}
    } finally { $pe.Dispose(); $stream.Dispose() }
}
function Get-ReleaseFeatureTypes {
    param([object[]]$Packages)
    $types=@{}; foreach ($package in $Packages) { foreach ($type in $package.metadata.types) { $types[$type.name]=$type } }
    foreach ($type in $types.Values) {
        $base=$type.base; $seen=@{}
        while ($base -and -not $seen.ContainsKey($base)) {
            if ($base -match '(^|\.)FeatureBase$') { $type.name; break }
            $seen[$base]=$true
            $base=if ($types.ContainsKey($base)) { $types[$base].base } else { $null }
        }
    }
}
