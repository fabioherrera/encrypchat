import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import type { Locale } from "@/i18n/config";
import { getDictionary } from "@/i18n/getDictionary";
import { localizedHref, type AppPath } from "@/i18n/path";
import type { LegalDoc } from "@/i18n/types";
import { SITE_NAME, SITE_URL } from "@/lib/site";

type Props = {
  doc: LegalDoc;
  locale: Locale;
  path: AppPath;
};

export function LegalArticle({ doc, locale, path }: Props) {
  const dict = getDictionary(locale);
  const related: AppPath[] =
    path === "/privacy" ? ["/terms", "/faq", "/download"] : ["/privacy", "/faq", "/download"];
  const relatedLabel: Record<string, string> = {
    "/privacy": dict.footer.privacy,
    "/terms": dict.footer.terms,
    "/faq": dict.footer.faq,
    "/download": dict.footer.download,
  };
  const pageLd = {
    "@context": "https://schema.org",
    "@type": "WebPage",
    name: doc.metaTitle,
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
          {section.blocks.map((block, index) =>
            Array.isArray(block) ? (
              <ul key={`${section.id}-${index}`}>
                {block.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            ) : (
              <p key={`${section.id}-${index}`}>{block}</p>
            ),
          )}
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
