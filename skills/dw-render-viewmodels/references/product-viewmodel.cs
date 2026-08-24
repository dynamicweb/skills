using System;
using System.Collections.Generic;
using Dynamicweb.Ecommerce.Products;

namespace Dynamicweb.Ecommerce.ProductCatalog;

/// <summary>
/// The product viewmodel represents a product and its data. The model covers basic things like Name, SKU, Description and the price.
/// The model also contains information about related product data like product relations, units, quantity prices, stock levels, assets, attributes and much more.
///
/// Most of the data is only loaded if and when used in a template or exposed in a web-api. The more of the properties that are used,
/// the more is loaded and that will have an impact on load performance. Each description of properties in this documentation contains
/// information about a potential performance overhead.
///
/// When rendering a list of products, the list size (i.e. 10 vs. 30 vs. 100 products on a list) can affect the performance of a product
/// list page since more data needs to be loaded.
///
/// WARNING: If multiple of the properties with performance overhead are used on the product list and many products are listed,
/// a lot of data will be loaded and affect performance. Limit the use of the properties with performance overhead on lists or use
/// the web-api to load additional information on demand when needed.
/// </summary>
public class ProductViewModel : FillableViewModelBase
{
    /// <summary>
    /// The product id.
    /// It's mapped from Product.Id.
    /// </summary>
    /// <remarks>Eager loaded - always available and using it does not come with an overhead.</remarks>
    public string Id { get; set; }

    /// <summary>
    /// The product variant id. The variant id is a combination of ids of variant options.
    /// I.e. if a product comes in different colors and sizes, the variant id will be a combination of 2 variant option ids (a color and a Size).
    /// It's mapped from Product.VariantId.
    /// </summary>
    /// <remarks>Eager loaded - always available and using it does not come with an overhead.</remarks>
    public string VariantId { get; set; }

    /// <summary>
    /// The product language id.
    /// It's mapped from Product.LanguageId.
    /// </summary>
    /// <remarks>Eager loaded - always available and using it does not come with an overhead.</remarks>
    public string LanguageId { get; set; }

    /// <summary>
    /// The product name.
    /// It's mapped from Product.Name.
    /// </summary>
    /// <remarks>Lazy loaded - only filled when using it but does not come with an overhead.</remarks>
    public string Name { get; set; }

    /// <summary>
    /// The product meta title. Often the same value as Name but can be overwritten in the meta title field.
    /// It's mapped from Product.Meta.Title, if that property is not null, otherwise it maps Product.Name.
    /// It's mapped to PageView.Meta.Title when being rendered.
    /// </summary>
    /// <remarks>Lazy loaded - only filled when using it but does not come with an overhead.</remarks>
    public string Title { get; set; }

    /// <summary>
    /// The short description of the product. Usually contains markup and multiple lines.
    /// It's mapped from Product.ShortDescription.
    /// </summary>
    /// <remarks>Lazy loaded - only filled when using it but does not come with an overhead.</remarks>
    public string ShortDescription { get; set; }

    /// <summary>
    /// The long description of the product. Usually contains markup and multiple lines.
    /// It's mapped from Product.LongDescription.
    /// </summary>
    /// <remarks>Lazy loaded - only filled when using it but does not come with an overhead.</remarks>
    public string LongDescription { get; set; }

    /// <summary>
    /// The product number or SKU of the product.
    /// It's mapped from Product.Number.
    /// </summary>
    /// <remarks>Lazy loaded - only filled when using it but does not come with an overhead.</remarks>
    public string Number { get; set; }

    /// <summary>
    /// The timestamp the product was created.
    /// It's mapped from Product.Created.
    /// </summary>
    /// <remarks>Lazy loaded - only filled when using it but does not come with an overhead.</remarks>
    public DateTime? Created { get; set; }

    /// <summary>
    /// The timestamp the product was last updated.
    /// It's mapped from Product.Updated.
    /// </summary>
    /// <remarks>Lazy loaded - only filled when using it but does not come with an overhead.</remarks>
    public DateTime? Updated { get; set; }

    /// <summary>
    /// The product price viewmodel which contains pricing, VAT, and currency information.
    /// </summary>
    public Dynamicweb.Frontend.PriceViewModel Price { get; set; }

    /// <summary>
    /// The product price before any discount is applied.
    /// </summary>
    public Dynamicweb.Frontend.PriceViewModel PriceBeforeDiscount { get; set; }

    /// <summary>
    /// The discount amount for this product.
    /// </summary>
    public double Discount { get; set; }

    /// <summary>
    /// Check if this product has an active discount.
    /// </summary>
    public bool HasDiscount()
    {
        return Price?.Price?.Value != PriceBeforeDiscount?.Price?.Value;
    }

    /// <summary>
    /// The default/primary image of the product as a file path string.
    /// </summary>
    public string DefaultImage { get; set; }

    /// <summary>
    /// Human-readable variant name combining all variant options (e.g., "Red, Large").
    /// </summary>
    public string VariantName { get; set; }

    /// <summary>
    /// The stock level / quantity available of this product.
    /// Only relevant if ProductType is Stock.
    /// </summary>
    public double StockLevel { get; set; }

    /// <summary>
    /// The type of product: Stock, Service, or NonStock.
    /// Stock products have inventory tracking; Service and NonStock do not.
    /// </summary>
    public ProductType ProductType { get; set; }

    /// <summary>
    /// If true, allows overselling (ignore StockLevel limit).
    /// </summary>
    public bool NeverOutOfstock { get; set; }

    /// <summary>
    /// If true, the product is marked as discontinued and should not be sold.
    /// </summary>
    public bool Discontinued { get; set; }

    /// <summary>
    /// The minimum quantity a customer must purchase at once.
    /// </summary>
    public double PurchaseMinimumQuantity { get; set; }

    /// <summary>
    /// The quantity must be a multiple of this step value.
    /// E.g., step 0.5 means customer can buy 0.5, 1.0, 1.5, etc.
    /// </summary>
    public double PurchaseQuantityStep { get; set; }

    /// <summary>
    /// Custom product fields grouped by category for display.
    /// </summary>
    public IDictionary<string, CategoryFieldViewModel> FieldDisplayGroups { get; set; }

    /// <summary>
    /// Get the URL link to this product's detail page.
    /// </summary>
    /// <param name="pageId">The product detail page ID.</param>
    /// <param name="useFriendlyUrls">Whether to use friendly URLs (default true).</param>
    public string GetProductLink(int pageId, bool useFriendlyUrls = true)
    {
        // Implementation provided by Dynamicweb
        throw new NotImplementedException();
    }
}
