using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Linq;
using Dynamicweb.Rendering;

namespace Dynamicweb.Frontend;

/// <summary>
/// The ItemViewModel class provides a robust way to represent the rendering context for items within Razor templates in Dynamicweb.
/// This class serves as the bridge between your data and the Razor templates, offering easy access to the fields, values, and other metadata
/// associated with the item being rendered.
/// </summary>
public class ItemViewModel : ViewModelBase
{
    public ItemViewModel()
    {
        Fields = new List<ItemFieldViewModel>();
    }

    /// <summary>
    /// Gets a list of fields and their values for this item.
    /// </summary>
    public IList<ItemFieldViewModel> Fields { get; set; }

    /// <summary>
    /// Gets the item id.
    /// </summary>
    public string? Id { get; set; }

    /// <summary>
    /// Gets the system name of the item type.
    /// </summary>
    public string? SystemName { get; set; }

    /// <summary>
    /// Gets the page id if the item is attached to a page, row or a paragraph.
    /// </summary>
    public int PageID { get; set; }

    /// <summary>
    /// Gets the paragraph id if the item is attached to a paragraph.
    /// </summary>
    public int ParagraphID { get; set; }

    /// <summary>
    /// Gets a link (URL) to the page or paragraph that this item is attached to.
    /// </summary>
    public string? Link { get; set; }

    /// <summary>
    /// Gets the value of the specified field as a boolean.
    /// </summary>
    public bool GetBoolean(string systemName)
    {
        return (GetField(systemName)?.GetBoolean()).GetValueOrDefault();
    }

    /// <summary>
    /// Returns the date and time data value of the specified field.
    /// </summary>
    public DateTime GetDateTime(string systemName)
    {
        return (GetField(systemName)?.GetDateTime()).GetValueOrDefault();
    }

    /// <summary>
    /// Returns the decimal value of the specified field.
    /// </summary>
    public decimal GetDecimal(string systemName)
    {
        return (GetField(systemName)?.GetDecimal()).GetValueOrDefault();
    }

    /// <summary>
    /// Returns the double value of the specified field.
    /// </summary>
    public double GetDouble(string systemName)
    {
        return (GetField(systemName)?.GetDouble()).GetValueOrDefault();
    }

    /// <summary>
    /// Returns the view model of the field.
    /// </summary>
    public ItemFieldViewModel? GetField(string systemName)
    {
        var field = Fields.FirstOrDefault(f => string.Equals(f.SystemName, systemName, StringComparison.OrdinalIgnoreCase));
        return field;
    }

    /// <summary>
    /// Returns the 32-bit integer value of the field.
    /// </summary>
    public int GetInt32(string systemName)
    {
        return (GetField(systemName)?.GetInt32()).GetValueOrDefault();
    }

    /// <summary>
    /// Returns the 64-bit integer value of the field.
    /// </summary>
    public long GetInt64(string systemName)
    {
        return (GetField(systemName)?.GetInt64()).GetValueOrDefault();
    }

    /// <summary>
    /// Returns an item view model of the field.
    /// </summary>
    public ItemViewModel? GetItem(string systemName)
    {
        return GetField(systemName)?.GetItem();
    }

    /// <summary>
    /// Returns a list of item view models of the field.
    /// </summary>
    public IList<ItemViewModel> GetItems(string systemName)
    {
        return GetField(systemName)?.GetItems() ?? [];
    }

    /// <summary>
    /// Returns the value of the field as string.
    /// </summary>
    public string? GetString(string systemName)
    {
        return GetField(systemName)?.GetString();
    }

    /// <summary>
    /// Returns the value of the field as string. Returns the default value if the field value is null or empty.
    /// </summary>
    [return: NotNullIfNotNull(nameof(defaultValue))]
    public string? GetString(string systemName, string? defaultValue)
    {
        var returnValue = GetString(systemName);
        if (string.IsNullOrEmpty(returnValue))
        {
            return defaultValue;
        }
        return returnValue;
    }

    /// <summary>
    /// Returns true if the value of the field is specified and a string is assigned to the passed out parameter.
    /// </summary>
    public bool TryGetString(string systemName, [NotNullWhen(true)] out string? value)
    {
        value = GetString(systemName);
        return !string.IsNullOrEmpty(value);
    }

    /// <summary>
    /// Returns a file view model of the field.
    /// </summary>
    public FileViewModel? GetFile(string systemName)
    {
        return GetField(systemName)?.GetFile();
    }

    /// <summary>
    /// Returns a list of file view models of the field.
    /// </summary>
    public IList<FileViewModel> GetFiles(string systemName)
    {
        return GetField(systemName)?.GetFiles() ?? [];
    }

    /// <summary>
    /// Returns true if the value of the field is specified and an imagefile view model is assigned to the passed out parameter.
    /// </summary>
    public bool TryGetImageFile(string systemName, [NotNullWhen(true)] out ImageFileViewModel? image)
    {
        image = GetField(systemName)?.GetFile() as ImageFileViewModel;
        return image is not null;
    }

    /// <summary>
    /// Returns a link view model of the field.
    /// </summary>
    public LinkViewModel? GetLink(string systemName)
    {
        return GetField(systemName)?.GetLink();
    }

    /// <summary>
    /// Returns true if the value of the field is specified and a link view model is assigned to the passed out parameter.
    /// </summary>
    public bool TryGetLink(string systemName, [NotNullWhen(true)] out LinkViewModel? link)
    {
        link = GetLink(systemName);
        return link is not null && !string.IsNullOrEmpty(link.Url);
    }

    /// <summary>
    /// Gets a button view model if the field is a button field
    /// </summary>
    public ButtonViewModel? GetButton(string systemName)
    {
        return GetField(systemName)?.GetButton();
    }

    /// <summary>
    /// Returns true if the value of the field is specified and a button view model is assigned to the passed out parameter.
    /// </summary>
    public bool TryGetButton(string systemName, [NotNullWhen(true)] out ButtonViewModel? button)
    {
        button = GetButton(systemName);
        return button is not null && button.Link is not null && !string.IsNullOrEmpty(button.Link.Url) && !string.IsNullOrEmpty(button.Label);
    }

    /// <summary>
    /// Returns a color view model of the field.
    /// </summary>
    public ColorViewModel? GetColor(string systemName)
    {
        return GetField(systemName)?.GetColor();
    }

    /// <summary>
    /// Returns the raw unmodified value from the database without any parsing
    /// </summary>
    public object? GetRawValue(string systemName)
    {
        return GetField(systemName)?.GetRawValue();
    }

    /// <summary>
    /// Returns the raw unmodified value from the database without any parsing but converted to string
    /// </summary>
    public string? GetRawValueString(string systemName)
    {
        return GetField(systemName)?.GetRawValueString();
    }
}
