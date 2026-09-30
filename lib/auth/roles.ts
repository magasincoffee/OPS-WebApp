import { supabaseRest } from "@/lib/supabase/rest";

type UserRole = {
  role_id: string;
};

type Role = {
  id: string;
  code: string;
};

export async function getCurrentRoles() {
  const memberships = await supabaseRest<UserRole[]>(
    "user_roles?select=role_id",
  );

  if (memberships.length === 0) {
    return new Set<string>();
  }

  const ids = memberships.map((membership) => membership.role_id).join(",");
  const roles = await supabaseRest<Role[]>(
    `roles?id=in.(${ids})&select=id,code`,
  );

  return new Set(roles.map((role) => role.code));
}
