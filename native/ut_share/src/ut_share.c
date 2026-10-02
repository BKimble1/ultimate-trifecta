/* UTShare: a tiny GDExtension (plain C against Godot's gdextension_interface.h)
 * that exposes the iOS share sheet to GDScript:
 *
 *     ClassDB.class_call_static("UTShare", "available") -> bool
 *     ClassDB.class_call_static("UTShare", "share", text, url) -> bool
 *
 * The class is abstract (never instantiated) and only has static methods, so
 * there is no object lifetime to manage. The platform work lives in
 * ut_share_ios.m (UIActivityViewController) or ut_share_stub.c (returns false).
 *
 * gdextension_interface.h is dumped from the pinned engine at build time
 * (tools/build_native.sh), so the binding always matches Godot 4.7.2. */
#include <stdlib.h>
#include <string.h>

#include "gdextension_interface.h"
#include "ut_share_platform.h"

#if defined(_WIN32)
#define UT_EXPORT __declspec(dllexport)
#else
#define UT_EXPORT __attribute__((visibility("default")))
#endif

/* Opaque engine types: StringName and String are one pointer wide. */
typedef struct {
	void *p;
} ut_opaque;

static GDExtensionClassLibraryPtr ut_library;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 ut_register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod ut_register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass ut_unregister_class;
static GDExtensionInterfaceStringNameNewWithLatin1Chars ut_string_name_new;
static GDExtensionInterfaceStringNewWithUtf8Chars ut_string_new;
static GDExtensionInterfaceStringToUtf8Chars ut_string_to_utf8;
static GDExtensionInterfaceVariantGetType ut_variant_get_type;
static GDExtensionTypeFromVariantConstructorFunc ut_string_from_variant;
static GDExtensionVariantFromTypeConstructorFunc ut_variant_from_bool;
static GDExtensionPtrDestructor ut_string_destroy;

static ut_opaque ut_class_name;      /* "UTShare" */
static ut_opaque ut_parent_name;     /* "Object" */
static ut_opaque ut_empty_name;      /* "" (StringName) */
static ut_opaque ut_empty_string;    /* "" (String) */
static ut_opaque ut_arg_names[2];    /* "text", "url" */
static ut_opaque ut_method_names[2]; /* "share", "available" */
static int ut_registered;

/* ------------------------------------------------------------- strings */

/* Copies a Godot String into a malloc'd UTF-8 C string (caller frees). */
static char *ut_utf8(GDExtensionConstStringPtr s) {
	GDExtensionInt n = ut_string_to_utf8(s, NULL, 0);
	char *out = (char *)malloc((size_t)n + 1);
	if (out == NULL) {
		return NULL;
	}
	ut_string_to_utf8(s, out, n);
	out[n] = '\0';
	return out;
}

static int ut_do_share(GDExtensionConstStringPtr text, GDExtensionConstStringPtr url) {
	char *t = ut_utf8(text);
	char *u = ut_utf8(url);
	int ok = (t != NULL && u != NULL) ? ut_platform_share(t, u) : 0;
	free(t);
	free(u);
	return ok;
}

static void ut_return_bool(GDExtensionVariantPtr r_return, int value) {
	GDExtensionBool b = value ? 1 : 0;
	ut_variant_from_bool(r_return, &b);
}

/* ------------------------------------------------------------- methods */

static void ut_share_call(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args,
		GDExtensionInt argc, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	(void)userdata;
	(void)instance;
	r_error->error = GDEXTENSION_CALL_OK;
	if (argc < 1) {
		r_error->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		r_error->expected = 1;
		return;
	}
	if (argc > 2) {
		r_error->error = GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
		r_error->expected = 2;
		return;
	}
	for (GDExtensionInt i = 0; i < argc; i++) {
		if (ut_variant_get_type(args[i]) != GDEXTENSION_VARIANT_TYPE_STRING) {
			r_error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
			r_error->argument = (int32_t)i;
			r_error->expected = GDEXTENSION_VARIANT_TYPE_STRING;
			return;
		}
	}
	ut_opaque text = { 0 };
	ut_opaque url = { 0 };
	ut_string_from_variant(&text, (GDExtensionVariantPtr)args[0]);
	if (argc > 1) {
		ut_string_from_variant(&url, (GDExtensionVariantPtr)args[1]);
	} else {
		ut_string_new(&url, "");
	}
	int ok = ut_do_share(&text, &url);
	ut_string_destroy(&text);
	ut_string_destroy(&url);
	ut_return_bool(r_return, ok);
}

static void ut_share_ptrcall(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr *args,
		GDExtensionTypePtr r_ret) {
	(void)userdata;
	(void)instance;
	*(GDExtensionBool *)r_ret = ut_do_share(args[0], args[1]) ? 1 : 0;
}

static void ut_available_call(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args,
		GDExtensionInt argc, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	(void)userdata;
	(void)instance;
	(void)args;
	if (argc > 0) {
		r_error->error = GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
		r_error->expected = 0;
		return;
	}
	r_error->error = GDEXTENSION_CALL_OK;
	ut_return_bool(r_return, ut_platform_available());
}

static void ut_available_ptrcall(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr *args,
		GDExtensionTypePtr r_ret) {
	(void)userdata;
	(void)instance;
	(void)args;
	*(GDExtensionBool *)r_ret = ut_platform_available() ? 1 : 0;
}

/* Abstract class: Godot never creates or frees instances, but the
 * destructor is mandatory in the creation info. */
static void ut_free_instance(void *class_userdata, GDExtensionClassInstancePtr instance) {
	(void)class_userdata;
	(void)instance;
}

/* ------------------------------------------------------------- registration */

static GDExtensionPropertyInfo ut_prop(GDExtensionVariantType type, ut_opaque *name) {
	GDExtensionPropertyInfo p;
	memset(&p, 0, sizeof(p));
	p.type = type;
	p.name = name;
	p.class_name = &ut_empty_name;
	p.hint = 0; /* PROPERTY_HINT_NONE */
	p.hint_string = &ut_empty_string;
	p.usage = 6; /* PROPERTY_USAGE_DEFAULT (STORAGE | EDITOR) */
	return p;
}

static void ut_register(void) {
	ut_string_name_new(&ut_class_name, "UTShare", 1);
	ut_string_name_new(&ut_parent_name, "Object", 1);
	ut_string_name_new(&ut_empty_name, "", 1);
	ut_string_new(&ut_empty_string, "");
	ut_string_name_new(&ut_arg_names[0], "text", 1);
	ut_string_name_new(&ut_arg_names[1], "url", 1);
	ut_string_name_new(&ut_method_names[0], "share", 1);
	ut_string_name_new(&ut_method_names[1], "available", 1);

	GDExtensionClassCreationInfo6 info;
	memset(&info, 0, sizeof(info));
	info.is_abstract = 1;
	info.is_exposed = 1;
	info.free_instance_func = ut_free_instance;
	ut_register_class(ut_library, &ut_class_name, &ut_parent_name, &info);

	GDExtensionPropertyInfo ret = ut_prop(GDEXTENSION_VARIANT_TYPE_BOOL, &ut_empty_name);
	GDExtensionPropertyInfo share_args[2] = {
		ut_prop(GDEXTENSION_VARIANT_TYPE_STRING, &ut_arg_names[0]),
		ut_prop(GDEXTENSION_VARIANT_TYPE_STRING, &ut_arg_names[1]),
	};
	GDExtensionClassMethodArgumentMetadata share_meta[2] = {
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
	};
	GDExtensionVariantPtr no_defaults = NULL;

	GDExtensionClassMethodInfo share;
	memset(&share, 0, sizeof(share));
	share.name = &ut_method_names[0];
	share.call_func = ut_share_call;
	share.ptrcall_func = ut_share_ptrcall;
	share.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC;
	share.has_return_value = 1;
	share.return_value_info = &ret;
	share.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	share.argument_count = 2;
	share.arguments_info = share_args;
	share.arguments_metadata = share_meta;
	/* url defaults to "" (the call path also accepts a single argument) */
	share.default_argument_count = 0;
	share.default_arguments = &no_defaults;
	ut_register_method(ut_library, &ut_class_name, &share);

	GDExtensionClassMethodInfo avail;
	memset(&avail, 0, sizeof(avail));
	avail.name = &ut_method_names[1];
	avail.call_func = ut_available_call;
	avail.ptrcall_func = ut_available_ptrcall;
	avail.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC;
	avail.has_return_value = 1;
	avail.return_value_info = &ret;
	avail.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	ut_register_method(ut_library, &ut_class_name, &avail);
	ut_registered = 1;
}

static void ut_initialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level == GDEXTENSION_INITIALIZATION_SCENE && !ut_registered) {
		ut_register();
	}
}

static void ut_deinitialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level == GDEXTENSION_INITIALIZATION_SCENE && ut_registered) {
		ut_unregister_class(ut_library, &ut_class_name);
		ut_string_destroy(&ut_empty_string);
		ut_registered = 0;
	}
}

#define UT_LOAD(var, type, name)                                   \
	do {                                                           \
		var = (type)(void *)get_proc_address(name);                \
		if (var == NULL) {                                         \
			return 0;                                              \
		}                                                          \
	} while (0)

UT_EXPORT GDExtensionBool ut_share_init(GDExtensionInterfaceGetProcAddress get_proc_address,
		GDExtensionClassLibraryPtr library, GDExtensionInitialization *r_initialization) {
	GDExtensionInterfaceGetVariantToTypeConstructor to_type;
	GDExtensionInterfaceGetVariantFromTypeConstructor from_type;
	GDExtensionInterfaceVariantGetPtrDestructor destructor;
	UT_LOAD(ut_register_class, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
	UT_LOAD(ut_register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
	UT_LOAD(ut_unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
	UT_LOAD(ut_string_name_new, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
	UT_LOAD(ut_string_new, GDExtensionInterfaceStringNewWithUtf8Chars, "string_new_with_utf8_chars");
	UT_LOAD(ut_string_to_utf8, GDExtensionInterfaceStringToUtf8Chars, "string_to_utf8_chars");
	UT_LOAD(ut_variant_get_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
	UT_LOAD(to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
	UT_LOAD(from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
	UT_LOAD(destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
	ut_string_from_variant = to_type(GDEXTENSION_VARIANT_TYPE_STRING);
	ut_variant_from_bool = from_type(GDEXTENSION_VARIANT_TYPE_BOOL);
	ut_string_destroy = destructor(GDEXTENSION_VARIANT_TYPE_STRING);
	if (ut_string_from_variant == NULL || ut_variant_from_bool == NULL || ut_string_destroy == NULL) {
		return 0;
	}
	ut_library = library;
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = NULL;
	r_initialization->initialize = ut_initialize;
	r_initialization->deinitialize = ut_deinitialize;
	return 1;
}
