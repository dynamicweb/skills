using System;
using System.Diagnostics.CodeAnalysis;
using System.Runtime.CompilerServices;
using Dynamicweb.Frontend;

namespace Dynamicweb.Frontend;

/// <summary>
/// Extension methods for ItemViewModel to ensure it is not null and throw an exception if it is.
/// </summary>
public static class ItemViewModelExtensions
{
    /// <summary>
    /// Ensures that the specified ItemViewModel is not null. Throws an exception if it is null.
    /// </summary>
    /// <param name="item">The ItemViewModel to check.</param>
    /// <param name="parameterName">The name of the parameter that is being checked. This is automatically provided by the compiler.</param>
    /// <returns>The original ItemViewModel if it is not null.</returns>
    /// <exception cref="ArgumentNullException">Thrown when the item is null.</exception>
    /// <example>
    /// <code>
    /// @{var item = Model.Item.RequireItem();}
    /// </code>
    /// </example>
    public static ItemViewModel RequireItem([NotNull] this ItemViewModel? item, [CallerArgumentExpression(nameof(item))] string? parameterName = null)
    {
        if (item is null)
            throw new ArgumentNullException(parameterName, "The item is required for this template.");
        return item;
    }

    /// <summary>
    /// Ensures that the specified ItemViewModel is not null. Throws an exception if it is null.
    /// </summary>
    /// <param name="item">The ItemViewModel to check.</param>
    /// <param name="parameterName">The name of the parameter that is being checked. This is automatically provided by the compiler.</param>
    /// <exception cref="ArgumentNullException">Thrown when the item is null.</exception>
    /// <example>
    /// <code>
    /// @Model.Item.Require();
    /// </code>
    /// </example>
    public static void Require([NotNull] this ItemViewModel? item, [CallerArgumentExpression(nameof(item))] string? parameterName = null)
    {
        _ = item.RequireItem(parameterName);
    }
}
