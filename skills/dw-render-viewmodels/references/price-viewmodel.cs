namespace Dynamicweb.Frontend
{
    /// <summary>
    /// Represents product pricing information with VAT, currency, and formatting.
    /// Always use PriceFormatted or related formatted properties in templates to respect locale and VAT rules.
    /// </summary>
    public class PriceViewModel
    {
        /// <summary>
        /// Gets or sets the price (typically the price the user will pay after VAT/discount rules).
        /// </summary>
        public PriceInfo? Price { get; set; }

        /// <summary>
        /// Gets or sets the price including VAT.
        /// </summary>
        public PriceInfo? PriceWithVat { get; set; }

        /// <summary>
        /// Gets or sets the price excluding VAT.
        /// </summary>
        public PriceInfo? PriceWithoutVat { get; set; }

        /// <summary>
        /// Gets or sets the VAT amount.
        /// </summary>
        public PriceInfo? Vat { get; set; }

        /// <summary>
        /// Gets or sets the VAT percentage.
        /// </summary>
        public VatInfo? VatPercent { get; set; }

        /// <summary>
        /// Gets or sets the currency for this price.
        /// </summary>
        public CurrencyInfo? Currency { get; set; }

        /// <summary>
        /// Gets or sets a value indicating whether to show prices with VAT.
        /// When false, show PriceWithoutVat; when true, show PriceWithVat.
        /// </summary>
        public bool ShowPricesWithVat { get; set; }

        /// <summary>
        /// Gets or sets a value indicating whether the VAT is reverse charged
        /// (typically for B2B or cross-border sales where buyer pays VAT).
        /// </summary>
        public bool ReverseChargeForVat { get; set; }

        /// <summary>
        /// Get a localized VAT label for display (e.g., "incl. VAT" or "excl. VAT").
        /// </summary>
        public bool TryGetVatLabel(out string label)
        {
            // Implementation provided by Dynamicweb
            label = null;
            return false;
        }

        /// <summary>
        /// Represents a price value with its formatted display variants.
        /// </summary>
        public class PriceInfo
        {
            /// <summary>
            /// The raw numeric price value.
            /// </summary>
            public double Value { get; set; }

            /// <summary>
            /// The formatted price string with currency symbol and locale-specific formatting.
            /// Example: "$99.99" or "99,99 €" (locale-dependent).
            /// Always use this for display.
            /// </summary>
            public string? Formatted { get; set; }

            /// <summary>
            /// The formatted price without currency symbol.
            /// Example: "99.99" or "99,99" (locale-dependent).
            /// Useful when rendering the symbol separately.
            /// </summary>
            public string? FormattedNoSymbol { get; set; }
        }

        /// <summary>
        /// Represents VAT percentage information.
        /// </summary>
        public class VatInfo
        {
            /// <summary>
            /// The VAT percentage as a decimal (e.g., 20 for 20% VAT).
            /// </summary>
            public double Percent { get; set; }

            /// <summary>
            /// The formatted VAT percentage for display (e.g., "20 %").
            /// </summary>
            public string? PercentFormatted { get; set; }
        }

        /// <summary>
        /// Represents currency information.
        /// </summary>
        public class CurrencyInfo
        {
            /// <summary>
            /// The currency symbol (e.g., "$", "€", "£").
            /// </summary>
            public string? Symbol { get; set; }

            /// <summary>
            /// The ISO currency code (e.g., "USD", "EUR", "GBP").
            /// </summary>
            public string? Code { get; set; }
        }
    }
}
