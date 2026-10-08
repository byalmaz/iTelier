/* Régression sur la vraie API libtatsu, sans signature réseau ni appareil. */
#include <libtatsu/tss.h>
#include <plist/plist.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

static plist_t component(int production, uint64_t revision, char digest)
{
    plist_t value = plist_new_dict();
    plist_dict_set_item(value, "EPRO", plist_new_bool(production));
    plist_dict_set_item(value, "FabRevision", plist_new_uint(revision));
    plist_dict_set_item(value, "Digest", plist_new_data(&digest, 1));
    plist_t info = plist_new_dict();
    plist_dict_set_item(info, "Path", plist_new_string("synthetic.bin"));
    plist_dict_set_item(value, "Info", info);
    return value;
}

static void check_selection(const char *name, int production, uint64_t revision,
                            const char *expected)
{
    plist_t request = plist_new_dict();
    plist_t parameters = plist_new_dict();
    plist_t manifest = plist_new_dict();
    plist_t sep = plist_new_dict();
    plist_dict_set_item(sep, "Digest", plist_new_data("S", 1));
    plist_dict_set_item(manifest, "SEP", sep);

    /* Ordre et clés du défaut réel : SepObject n'a ni EPRO ni FabRevision. */
    plist_t parasite = plist_new_dict();
    plist_dict_set_item(parasite, "Digest", plist_new_data("P", 1));
    plist_dict_set_item(manifest, "Yonkers,SepObject", parasite);
    plist_dict_set_item(manifest, "Yonkers,SysTopPatchDevelopment", component(0, 7, 'D'));
    plist_dict_set_item(manifest, "Yonkers,SysTopPatchWrongRevision", component(1, 8, 'W'));
    plist_dict_set_item(manifest, "Yonkers,SysTopPatchProduction", component(1, 7, 'R'));
    plist_dict_set_item(parameters, "Manifest", manifest);
    plist_dict_set_item(parameters, "Yonkers,ProductionMode", plist_new_bool(production));
    plist_dict_set_item(parameters, "Yonkers,FabRevision", plist_new_uint(revision));
    plist_dict_set_item(parameters, "Yonkers,AllowOfflineBoot", plist_new_bool(0));
    plist_dict_set_item(parameters, "Yonkers,BoardID", plist_new_uint(1));
    plist_dict_set_item(parameters, "Yonkers,ChipID", plist_new_uint(2));
    plist_dict_set_item(parameters, "Yonkers,ECID", plist_new_uint(3));
    plist_dict_set_item(parameters, "Yonkers,Nonce", plist_new_data("N", 1));
    plist_dict_set_item(parameters, "Yonkers,PatchEpoch", plist_new_uint(1));
    plist_dict_set_item(parameters, "Yonkers,ReadECKey", plist_new_bool(0));
    plist_dict_set_item(parameters, "Yonkers,ReadFWKey", plist_new_bool(0));

    char *selected = NULL;
    int result = tss_request_add_yonkers_tags(request, parameters, NULL, &selected);
    int valid = expected ? result == 0 && selected && strcmp(selected, expected) == 0
                         : result < 0 && selected == NULL;
    if (plist_dict_get_item(request, "Yonkers,SepObject")) {
        valid = 0;
    }
    if (expected) {
        plist_t entry = plist_dict_get_item(request, expected);
        if (!entry || plist_dict_get_item(entry, "Info")) {
            valid = 0;
        }
    }
    if (!valid) {
        fprintf(stderr, "%s: sélection %s, attendue %s (parasite Yonkers,SepObject)\n",
                name, selected ? selected : "aucune", expected ? expected : "aucune");
        failures++;
    }
    free(selected);
    plist_free(parameters);
    plist_free(request);
}

int main(void)
{
    check_selection("production", 1, 7, "Yonkers,SysTopPatchProduction");
    check_selection("développement", 0, 7, "Yonkers,SysTopPatchDevelopment");
    check_selection("révision", 1, 8, "Yonkers,SysTopPatchWrongRevision");
    check_selection("aucune variante compatible", 1, 99, NULL);
    if (failures) {
        return 1;
    }
    puts("4 sélections Yonkers vérifiées sur libtatsu, sans appareil ni réseau.");
    return 0;
}
