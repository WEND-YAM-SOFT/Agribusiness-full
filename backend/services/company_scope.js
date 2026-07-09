async function getCompanyIdForUser(client, userId) {
  const { data, error } = await client
    .from('profiles')
    .select('company_id')
    .eq('id', userId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data?.company_id) {
    throw new Error('Profil utilisateur sans company_id');
  }
  return data.company_id;
}

module.exports = {
  getCompanyIdForUser,
};
