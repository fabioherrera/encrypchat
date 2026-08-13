import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import type { Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { localizedHref, type AppPath } from "@/i18n/path";
import type { LegalDoc, LegalSectionLink } from "@/i18n/types";
import { SITE_NAME, SITE_URL } from "@/lib/site";

type Props = {
  doc: LegalDoc;
  locale: Locale;
  path: AppPath;
  /** `TechArticle` for the threat model; the legal pages stay plain pages. */
  schemaType?: "WebPage" | "TechArticle";
};

const RELATED: AppPath[] = ["/privacy", "/terms", "/security", "/faq", "/download"];

export function LegalArticle({ doc, locale, path, schemaType = "WebPage" }: Props) {
  const dict = getDictionary(locale);
  const related = RELATED.filter((target) => target !== path);
  const relatedLabel: Record<string, string> = {
    "/privacy": dict.footer.privacy,
    "/terms": dict.footer.terms,
    "/security": dict.footer.security,
    "/faq": dict.footer.faq,
    "/download": dict.footer.download,
  };
  const sectionHref = (link: LegalSectionLink) =>
    `${localizedHref(locale, link.path)}${link.hash ? `#${link.hash}` : ""}`;
  const pageLd = {
    "@context": "https://schema.org",
    "@type": schemaType,
    name: doc.metaTitle,
    headline: doc.h1,
    description: doc.metaDescription,
    url: `${SITE_URL}${localizedHref(locale, path)}`,
    inLanguage: locale,
    dateModified: doc.updatedIso,
    isPartOf: { "@type": "WebSite", name: SITE_NAME, url: SITE_URL },
    publisher: { "@type": "Organization", name: SITE_NAME, url: SITE_URL },
  };

  return (
    <article className="section prose">
      <JsonLd data={pageLd} />
      <h1>{doc.h1}</h1>
      <p className="muted">{doc.updated}</p>
      <p>{doc.summary}</p>
      <p className="muted">{doc.disclaimer}</p>

      {doc.sections.map((section) => (
        <section key={section.id} className="legalSection">
          <h2 id={section.id}>{section.title}</h2>
          {section.blocks.map((block, index) => {
            const key = `${section.id}-${index}`;
            if (typeof block === "string") return <p key={key}>{block}</p>;
            if (Array.isArray(block)) {
              return (
                <ul key={key}>
                  {block.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              );
            }
            return (
              <ol key={key}>
                {block.ordered.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ol>
            );
          })}
          {section.links ? (
            <p className="sectionLinks">
              {section.links.map((link) => (
                <Link key={sectionHref(link)} href={sectionHref(link)}>
                  {link.label}
                </Link>
              ))}
            </p>
          ) : null}
        </section>
      ))}

      <nav className="legalNav" aria-label={dict.legal.relatedAria}>
        {related.map((target) => (
          <Link key={target} href={localizedHref(locale, target)}>
            {relatedLabel[target]}
          </Link>
        ))}
      </nav>
    </article>
  );
}
