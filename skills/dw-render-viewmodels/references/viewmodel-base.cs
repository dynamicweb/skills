using Dynamicweb.Core;

namespace Dynamicweb.Rendering
{
    /// <summary>
    /// ViewModelBase represents a view model that can be used for rendering templates using a model instead of template tags.
    /// Inherit from this base class to create a view model.
    /// </summary>
    /// <example>
    /// <code title="How to implement a custom view model" source="..\..\..\Features\Content\Dynamicweb.Examples\Rendering\ViewModelSample.cs" lang="CS"></code>
    /// <code title="How to use a custom view model" source="..\..\..\Features\Content\Dynamicweb.Examples\Rendering\ViewModelTemplateSample.cs" lang="CS"></code>
    /// </example>
    public abstract class ViewModelBase
    {
        public virtual string ToJson()
        {
            return Converter.Serialize(this);
        }
    }
}
