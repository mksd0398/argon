// Home-screen metaobject types (spec §2) as Admin API MetaobjectDefinitionCreateInput /
// MetaobjectCreateInput. Pure data and pure functions; Task 4 sends them to the Admin API.
// ponytail: Admin field definitions have no default values, so the spec's "default hero" and
// "default 8" are applied by the app when the field is empty, not here.

const single = "single_line_text_field";
const f = (key, name, type = single, extra = {}) => ({ key, name, type, ...extra });
const check = (name, value) => ({ name, value });
const choices = (...values) => [check("choices", JSON.stringify(values))];

const define = (type, name, displayNameKey, fieldDefinitions) => ({
  type,
  name,
  displayNameKey,
  access: { storefront: "PUBLIC_READ" },
  fieldDefinitions,
});

export const SECTION_DEFINITIONS = [
  define("mobile_banner", "Mobile banner", "heading", [
    f("image", "Image", "file_reference", { validations: [check("file_type_options", JSON.stringify(["Image"]))] }),
    f("heading", "Heading"),
    f("text", "Text", "multi_line_text_field"),
    f("button_label", "Button label"),
    f("link", "Link", single, { description: "A store path like /collections/sale, or a full URL." }),
    f("style", "Style", single, { validations: choices("hero", "card") }),
  ]),
  define("mobile_products", "Mobile products", "heading", [
    f("heading", "Heading"),
    f("collection", "Collection", "collection_reference"),
    f("products", "Products", "list.product_reference"),
    f("style", "Style", single, { validations: choices("carousel", "grid") }),
    f("limit", "Limit", "number_integer", { validations: [check("min", "1"), check("max", "24")] }),
  ]),
  define("mobile_collections", "Mobile collections", "heading", [
    f("heading", "Heading"),
    f("collections", "Collections", "list.collection_reference", { required: true }),
  ]),
];

// sectionDefinitionIds: GIDs of the three section definitions, known only after they are created.
export const screenDefinition = (sectionDefinitionIds) =>
  define("mobile_screen", "Mobile screen", "title", [
    f("title", "Title", single, { required: true }),
    f("sections", "Sections", "list.mixed_reference", {
      required: true,
      validations: [check("metaobject_definition_ids", JSON.stringify(sectionDefinitionIds))],
    }),
  ]);

const entry = (type, handle, values) => ({
  type,
  handle,
  fields: Object.entries(values).map(([key, value]) => ({ key, value })),
});

// collections: [{ id, productsCount }]. The screen needs the created section entry ids, hence a function.
export function buildSeed({ shopName, collections }) {
  const ids = collections.filter((c) => c.productsCount > 0).map((c) => c.id);
  const sections = [
    entry("mobile_banner", "home-hero", {
      heading: shopName,
      text: "Add an image and edit this banner in Content → Metaobjects → Mobile banner.",
      style: "hero",
    }),
  ];
  if (ids.length) {
    sections.push(
      entry("mobile_collections", "home-collections", {
        heading: "Shop by collection",
        collections: JSON.stringify(ids.slice(0, 6)),
      }),
      entry("mobile_products", "home-featured", {
        heading: "Featured",
        collection: ids[0],
        style: "carousel",
        limit: "8",
      }),
    );
  }
  return {
    sections,
    screen: (sectionIds) => entry("mobile_screen", "home", { title: "Home", sections: JSON.stringify(sectionIds) }),
  };
}
