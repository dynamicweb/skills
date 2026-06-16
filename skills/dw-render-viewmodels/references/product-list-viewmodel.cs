using System.Collections.Generic;

namespace Dynamicweb.Ecommerce.ProductCatalog;

/// <summary>
/// The top-level view model for a product list page — contains the products, the active group,
/// sub-groups, facets, pagination data, and spell-checker suggestions.
///
/// This is the primary model rendered by product list templates.
/// </summary>
/// <remarks>
/// Use ProductListViewModelExtensions for helpers such as GetUriWithoutSelectedFacets and GetSubOrRootGroups.
/// </remarks>
public class ProductListViewModel : FillableViewModelBase
{
    /// <summary>
    /// Gets or sets the product group currently being browsed.
    /// Populated when the request includes a GroupID query parameter (e.g. ?GroupID=group1).
    /// Null for pure search results (e.g. ?q=shirt) where no group context exists.
    /// </summary>
    public ProductGroupViewModel Group { get; set; }

    /// <summary>
    /// Gets or sets the direct child groups of Group.
    /// Empty when the current group has no sub-groups or when browsing a search result.
    /// Use ProductListViewModelExtensions.GetSubOrRootGroups to fall back to
    /// shop root groups when no sub-groups exist.
    /// </summary>
    public IList<ProductGroupViewModel> SubGroups { get; set; }

    /// <summary>
    /// Gets or sets the products on the current page of the result set.
    /// Null when the Products property was not requested via settings.
    /// </summary>
    public IList<ProductViewModel> Products { get; set; }

    /// <summary>
    /// Gets or sets the number of products per page as configured in the catalog paragraph.
    /// 0 means all products are returned without pagination.
    /// </summary>
    public int PageSize { get; set; }

    /// <summary>
    /// Gets or sets the total number of pages in the result set.
    /// 0 or 1 means the result is not paginated.
    /// </summary>
    public int PageCount { get; set; }

    /// <summary>
    /// Gets or sets the 1-based current page number (e.g. 1 for the first page).
    /// </summary>
    public int CurrentPage { get; set; }

    /// <summary>
    /// Gets or sets the total number of products across all pages in the result set.
    /// Use this to display a "Showing X of Y products" message.
    /// </summary>
    public int TotalProductsCount { get; set; }

    /// <summary>
    /// Gets or sets the index field name by which the list is currently sorted.
    /// When sorted by multiple fields only the primary field is exposed here.
    /// Common values: "Name", "Price", "Created", "OrderCount", "OrderCountGrowth"
    /// </summary>
    public string SortBy { get; set; }

    /// <summary>
    /// Gets or sets the sort direction for the primary sort field — typically "ASC" or "DESC".
    /// When sorted by multiple fields only the primary sort direction is exposed here.
    /// </summary>
    public string SortOrder { get; set; }

    /// <summary>
    /// Gets or sets the spell-checker alternative search terms returned when the search query
    /// produced few or no results. Empty when no suggestions are available.
    /// </summary>
    public IList<string> SpellCheckerSuggestions { get; set; }

    /// <summary>
    /// Gets or sets the facet groups available for the current search result.
    /// Null when facets were not requested via settings.
    /// Iterate over this to render filter sidebars; use GetUriWithoutSelectedFacets to build
    /// a "Clear all filters" link.
    /// </summary>
    public IList<FacetGroupViewModel> FacetGroups { get; set; }
}

/// <summary>
/// Represents a product group (category) for navigation.
/// </summary>
public class ProductGroupViewModel
{
    public string Id { get; set; }
    public string Name { get; set; }
}

/// <summary>
/// Represents a filterable facet group (e.g., "Color", "Size", "Price Range").
/// </summary>
public class FacetGroupViewModel
{
    public IList<FacetViewModel> Facets { get; set; }
}

/// <summary>
/// Represents a single facet (filter) within a facet group.
/// </summary>
public class FacetViewModel
{
    /// <summary>
    /// The display name of this facet (e.g., "Color", "Price").
    /// </summary>
    public string Name { get; set; }

    /// <summary>
    /// The query parameter name to use in URLs (e.g., "color", "price").
    /// </summary>
    public string QueryParameter { get; set; }

    /// <summary>
    /// How to render this facet: typically "Colors" for color swatches, or "Checkboxes" for text/list.
    /// </summary>
    public string RenderType { get; set; }

    /// <summary>
    /// The available filter options for this facet.
    /// </summary>
    public IList<FacetOptionViewModel> Options { get; set; }
}

/// <summary>
/// Represents a single option within a facet (e.g., "Red" for Color facet).
/// </summary>
public class FacetOptionViewModel
{
    /// <summary>
    /// The value to send in query parameter (e.g., "red").
    /// </summary>
    public string Value { get; set; }

    /// <summary>
    /// The display label (e.g., "Red").
    /// </summary>
    public string Label { get; set; }

    /// <summary>
    /// Whether this option is currently selected.
    /// </summary>
    public bool Selected { get; set; }

    /// <summary>
    /// The number of products matching this option.
    /// </summary>
    public int Count { get; set; }
}
