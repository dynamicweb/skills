using System.Collections.Generic;
using Dynamicweb.Rendering;

namespace Dynamicweb.Frontend;
/// <summary>
/// ParagraphViewModel represents the rendering context used when a paragraph is rendered.
/// </summary>
/// <seealso cref="ViewModelBase" />
/// <remarks>Contains rendering context information of the rendering <see cref="Dynamicweb.Content.Paragraph" /></remarks>
public class ParagraphViewModel : ViewModelBase
{
    public ParagraphViewModel()
    {

    }

    /// <summary>
    /// Gets the count of columns in the current grid row.
    /// </summary>
    /// <value>The number of grid row columns, e.g. 3 </value>
    public int GridRowColumnCount { get; set; }

    /// <summary>
    /// Gets the count of columns in the current grid row.
    /// </summary>
    /// <value>The number of grid row columns, e.g. 3 </value>
    public int GridColumnWidth { get; set; }

    /// <summary>
    /// Gets the position of this paragraph in the current grid row.
    /// </summary>
    /// <value>The grid column number, e.g. 2 (out of 3)</value>
    public int GridColumnNumber { get; set; }

    /// <summary>
    /// Gets the name of the content placeholder where this paragraph is located.
    /// </summary>
    /// <value>The name of the container, e.g. 'myContainer'.</value>
    /// <remarks>If the container does not exist in the layout currently being rendered, the paragraph is rendered to the default placeholder</remarks>
    public string? Container { get; set; }

    /// <summary>
    /// Gets the total count of paragraphs under the content placeholder where this paragraph is located.
    /// </summary>
    /// <value>A number indicating how many paragraphs are rendered in the container</value>
    /// <seealso cref="Container"/>
    public int ContainerCount { get; set; } = 1;

    /// <summary>
    /// Gets the sort order of this paragraph under the current content placeholder.
    /// </summary>
    /// <value>A number starting from 1 that represents this paragraphs sort in the current content placeholder</value>
    /// <remarks>Can potentially be a negative integer.</remarks>
    /// <seealso cref="Container"/>
    public int ContainerSort { get; set; } = 1;

    /// <summary>
    /// Gets or sets the sort order of the paragraph.
    /// </summary>
    /// <value>An integer representing the sort order for displaying paragraph on the page it belongs.</value>
    public int Sort { get; set; }

    /// <summary>
    /// Gets the header (name) of the paragraph.
    /// </summary>
    /// <value>The header or name e.g 'my paragraph name'.</value>
    public string? Header { get; set; }

    /// <summary>
    /// Gets the paragraph id, it's mapped from <see cref="Dynamicweb.Content.Paragraph"/>'s <see cref="Dynamicweb.Core.Entity{TKey}.ID"/>
    /// </summary>
    /// <value>The paragraph id e.g. 1.</value>
    public int ID { get; set; }

    /// <summary>
    /// Gets the relative path to the image selected or linked on the paragraph.
    /// </summary>
    /// <value>The path to the image, e.g. /Files/Images/Image.jpg or http://domain.com/image.jpg. </value>
    public string? Image { get; set; }

    /// <summary>
    /// Gets the alt-text of the image.
    /// </summary>
    /// <value> Any string, e.g. "image of a penguin with our yellow hat on".</value>
    public string? ImageAlt { get; set; }

    /// <summary>
    /// Gets the image caption.
    /// </summary>
    /// <value>The image caption e.g "Electric bike - EV1 Bike".</value>
    public string? ImageCaption { get; set; }

    /// <summary>
    /// If this paragraph has an item associated with it, this property gives you access to the item viewmodel which is used to access item content.
    /// </summary>
    /// <value>The Item-viewmodel or null.</value>
    public ItemViewModel? Item { get; set; }

    /// <summary>
    /// Gets the item id.
    /// </summary>
    /// <seealso cref="Dynamicweb.Content.Paragraph.ItemId"/>
    /// <value>E.g. 5</value>
    public string? ItemId { get; set; }

    /// <summary>
    /// Gets the item type system name.
    /// </summary>
    /// <seealso cref="Dynamicweb.Content.Paragraph.ItemType"/>.
    /// <value>E.g. 'myItemtype'</value>
    public string? ItemType { get; set; }

    /// <summary>
    /// Gets the default paragraph rich text field content.
    /// </summary>
    /// <value>The text e.g. "this is the paragraph text".</value>
    public string? Text { get; set; }

    /// <summary>
    /// Returns the module (app) output of this paragraph if a module is attached.
    /// </summary>
    /// <returns>A string of html containing the rendering of the module. If no module is attached then an empty string is returned</returns>
    /// <remarks>This method only executes the module once. If it is called more than once for each instance of a <see cref="ParagraphViewModel"/>, the result of the first call is returned.</remarks>
    public string? GetModuleOutput()
    {
        return moduleOutput;
    }

    private string? moduleOutput;

    internal void SetModuleOutput(string output)
    {
        moduleOutput = output;
    }
}
